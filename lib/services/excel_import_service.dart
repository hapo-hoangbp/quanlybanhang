import 'dart:io';
import 'dart:isolate';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart' show Excel, Data, TextCellValue, IntCellValue, DoubleCellValue;
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';

import '../models/product.dart';

class ExcelImportResult {
  final List<Product> products;
  final int skipped;
  final String? error;

  ExcelImportResult({
    required this.products,
    this.skipped = 0,
    this.error,
  });
}

class ExcelImportService {
  static Future<ExcelImportResult> pickAndImport() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      allowMultiple: false,
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return ExcelImportResult(products: [], error: 'Chưa chọn file');
    }

    final file = result.files.single;
    if (file.bytes != null && file.bytes!.isNotEmpty) {
      return importFromBytes(file.bytes!);
    }
    final path = file.path;
    if (path != null && path.isNotEmpty) {
      return importFromPath(path);
    }
    return ExcelImportResult(products: [], error: 'Không đọc được file');
  }

  static Future<ExcelImportResult> importFromPath(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      return importFromBytes(bytes);
    } catch (e) {
      return ExcelImportResult(products: [], error: 'Lỗi đọc file: $e');
    }
  }

  static Future<ExcelImportResult> importFromBytes(List<int> bytes) async {
    try {
      final xlsxValidationError = _getXlsxValidationError(bytes);
      if (xlsxValidationError != null) {
        return ExcelImportResult(
          products: [],
          error: xlsxValidationError,
        );
      }

      late final Excel excel;
      try {
        // Decode trong isolate riêng để cô lập lỗi parser từ package excel.
        excel = await Isolate.run(() => Excel.decodeBytes(bytes));
      } catch (e) {
        try {
          // Workaround cho các file có ô string rỗng khiến package excel ném null-check.
          final sanitized = await Isolate.run(() => _sanitizeExcelBytes(bytes));
          excel = await Isolate.run(() => Excel.decodeBytes(sanitized));
        } catch (e2) {
          return ExcelImportResult(
            products: [],
            error: 'Không thể đọc nội dung file Excel. $e2. '
                'File có thể bị lỗi hoặc không tương thích. '
                'Hãy mở file và Save As lại dạng .xlsx rồi thử lại.',
          );
        }
      }

      final sheet = excel.tables.keys.isNotEmpty ? (excel.tables[excel.tables.keys.first] ?? excel.tables.values.first) : null;
      if (sheet == null || sheet.rows.isEmpty) {
        return ExcelImportResult(products: [], error: 'File Excel trống');
      }

      int nameCol = -1;
      int codeCol = -1;
      int priceCol = -1;
      int stockCol = -1;
      int imageCol = -1;
      int dataStartRow = 0;

      final firstRow = sheet.rows.isNotEmpty ? sheet.rows[0] : <Data?>[];
      final headerTexts = firstRow.map((c) => _cellValue(c)?.toString().toLowerCase().trim() ?? '').toList();

      // Chỉ map theo yêu cầu: Mã hàng, Tên hàng, Giá bán, Tồn kho, Hình ảnh.
      final nameKeywords = ['tên hàng', 'ten hang', 'tên sp', 'tên sản phẩm', 'sản phẩm', 'san pham'];
      final codeKeywords = ['mã hàng', 'ma hang', 'mã sp', 'mã sản phẩm', 'code', 'sku'];
      final priceKeywords = ['giá bán', 'gia ban', 'đơn giá', 'don gia', 'giá', 'gia'];
      final stockKeywords = ['tồn kho', 'ton kho', 'tồn', 'ton'];
      final imageKeywords = ['hình ảnh', 'hinh anh', 'ảnh', 'anh', 'image', 'url ảnh', 'url hinh anh'];

      for (var i = 0; i < headerTexts.length; i++) {
        final h = headerTexts[i];
        if (nameCol < 0 && nameKeywords.any((k) => h.contains(k))) nameCol = i;
        if (codeCol < 0 && codeKeywords.any((k) => h.contains(k))) codeCol = i;
        if (priceCol < 0 && priceKeywords.any((k) => h.contains(k))) priceCol = i;
        if (stockCol < 0 && stockKeywords.any((k) => h.contains(k))) stockCol = i;
        if (imageCol < 0 && imageKeywords.any((k) => h.contains(k))) imageCol = i;
      }

      // Chế độ import "dễ dãi" theo file hiện tại:
      // 0: mã hàng, 1: tên hàng, 2: giá bán, 3: giá vốn, 4: tồn kho, 5: hình ảnh(url1,url2,...)
      if (nameCol >= 0 || codeCol >= 0 || priceCol >= 0 || stockCol >= 0 || imageCol >= 0) {
        dataStartRow = 1;
      } else {
        codeCol = 0;
        nameCol = 1;
        priceCol = 2;
        stockCol = 4;
        imageCol = 5;
        dataStartRow = 0;
      }

      // Điền fallback cho các cột còn thiếu để tăng tỉ lệ import thành công.
      codeCol = codeCol >= 0 ? codeCol : 0;
      nameCol = nameCol >= 0 ? nameCol : 1;
      priceCol = priceCol >= 0 ? priceCol : 2;
      stockCol = stockCol >= 0 ? stockCol : 4;
      imageCol = imageCol >= 0 ? imageCol : 5;

      final products = <Product>[];
      var skipped = 0;
      final existingCodes = <String>{};

      for (var r = dataStartRow; r < sheet.rows.length; r++) {
        final row = sheet.rows[r];
        final name = _cellValue(nameCol < row.length ? row[nameCol] : null)?.toString().trim();
        var code = _cellValue(codeCol >= 0 && codeCol < row.length ? row[codeCol] : null)?.toString().trim() ?? '';
        final priceRaw = _cellValue(priceCol < row.length ? row[priceCol] : null);
        final stockRaw = stockCol >= 0 && stockCol < row.length ? _cellValue(row[stockCol]) : null;
        final imageRaw = imageCol >= 0 && imageCol < row.length ? _cellValue(row[imageCol]) : null;

        if ((name == null || name.isEmpty) && code.isEmpty) {
          skipped++;
          continue;
        }

        final price = _parsePrice(priceRaw) ?? 0;

        if (code.isEmpty) code = 'SP${(r - dataStartRow + 1).toString().padLeft(4, '0')}';
        var uniqueCode = code;
        var suffix = 1;
        while (existingCodes.contains(uniqueCode)) {
          uniqueCode = '$code-$suffix';
          suffix++;
        }
        existingCodes.add(uniqueCode);

        final stock = _parseInt(stockRaw) ?? 0;
        final imagePath = _pickFirstImageUrl(imageRaw?.toString());

        products.add(Product(
          id: const Uuid().v4(),
          name: (name == null || name.isEmpty) ? uniqueCode : name,
          code: uniqueCode,
          price: price,
          stock: stock,
          imagePath: (imagePath != null && imagePath.isNotEmpty) ? imagePath : null,
        ));
      }

      return ExcelImportResult(products: products, skipped: skipped);
    } catch (e) {
      return ExcelImportResult(products: [], error: 'Lỗi đọc file: $e');
    }
  }

  static dynamic _cellValue(Data? cell) {
    if (cell == null) return null;
    final v = cell.value;
    if (v == null) return null;
    return switch (v) {
      TextCellValue() => v.value.text ?? v.value.toString(),
      IntCellValue(:final value) => value,
      DoubleCellValue(:final value) => value,
      _ => v.toString(),
    };
  }

  static double? _parsePrice(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    final s = value.toString().replaceAll(',', '.').replaceAll(RegExp(r'[^\d.]'), '');
    return double.tryParse(s);
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    final s = value.toString().replaceAll(RegExp(r'[^\d-]'), '');
    return int.tryParse(s);
  }

  static String? _pickFirstImageUrl(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final first = trimmed.split(',').map((e) => e.trim()).firstWhere(
          (e) => e.isNotEmpty,
          orElse: () => '',
        );
    if (first.isEmpty) return null;
    return first;
  }

  static bool _looksLikeXlsxZip(List<int> bytes) {
    if (bytes.length < 4) return false;
    // .xlsx là file ZIP, thường bắt đầu bằng chữ ký "PK\x03\x04" (hoặc các biến thể PK\x05\x06 / PK\x07\x08).
    final b0 = bytes[0];
    final b1 = bytes[1];
    final b2 = bytes[2];
    final b3 = bytes[3];
    if (b0 != 0x50 || b1 != 0x4B) return false;
    return (b2 == 0x03 && b3 == 0x04) || (b2 == 0x05 && b3 == 0x06) || (b2 == 0x07 && b3 == 0x08);
  }

  static String? _getXlsxValidationError(List<int> bytes) {
    if (!_looksLikeXlsxZip(bytes)) {
      return 'File không đúng định dạng Excel (.xlsx). '
          'Vui lòng mở file và Save As lại dạng Excel Workbook (.xlsx), rồi import lại.';
    }

    try {
      final archive = ZipDecoder().decodeBytes(bytes, verify: false);
      final names = archive.files.map((f) => f.name).toSet();
      final hasWorkbook = names.contains('xl/workbook.xml');
      final hasContentTypes = names.contains('[Content_Types].xml');
      final hasRels = names.contains('_rels/.rels');

      if (hasWorkbook && hasContentTypes && hasRels) {
        return null;
      }

      final looksLikeNumbers = names.any((n) => n.startsWith('Index/')) && names.any((n) => n.endsWith('.iwa'));
      if (looksLikeNumbers) {
        return 'File này được tạo bởi Apple Numbers và không phải workbook .xlsx chuẩn để import trực tiếp. '
            'Bạn hãy mở file trong Numbers/Excel và Export/Save As lại dạng Excel (.xlsx), rồi thử lại.';
      }

      return 'File nén này không có cấu trúc workbook .xlsx hợp lệ. '
          'Vui lòng mở file và Save As lại dạng Excel Workbook (.xlsx), rồi import lại.';
    } catch (_) {
      return 'Không thể đọc cấu trúc file Excel. '
          'Vui lòng mở file và Save As lại dạng Excel Workbook (.xlsx), rồi import lại.';
    }
  }

  static List<int> _sanitizeExcelBytes(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final rebuilt = Archive();

    final emptyStrCellSelfClosing = RegExp(r'<c[^>]*\st="str"[^>]*/>');
    final emptyStrCellVSelfClosing = RegExp(r'<c[^>]*\st="str"[^>]*>\s*<v\s*/>\s*</c>');
    final emptyStrCellVEmpty = RegExp(r'<c[^>]*\st="str"[^>]*>\s*<v>\s*</v>\s*</c>');

    for (final file in archive.files) {
      if (!file.isFile) {
        rebuilt.addFile(file);
        continue;
      }
      final isWorksheetXml = file.name.startsWith('xl/worksheets/') && file.name.endsWith('.xml');
      final isStylesXml = file.name == 'xl/styles.xml';
      final content = file.content;
      if (content is! List<int>) {
        rebuilt.addFile(file);
        continue;
      }

      List<int> outputBytes = content;
      if (isWorksheetXml) {
        final xml = utf8.decode(content, allowMalformed: true);
        final sanitized = xml.replaceAll(emptyStrCellSelfClosing, '').replaceAll(emptyStrCellVSelfClosing, '').replaceAll(emptyStrCellVEmpty, '');
        if (sanitized != xml) {
          outputBytes = utf8.encode(sanitized);
        }
      } else if (isStylesXml) {
        final xml = utf8.decode(content, allowMalformed: true);
        final sanitized = _sanitizeStylesXml(xml);
        if (sanitized != xml) {
          outputBytes = utf8.encode(sanitized);
        }
      }

      rebuilt.addFile(ArchiveFile(file.name, outputBytes.length, outputBytes));
    }

    final encoded = ZipEncoder().encode(rebuilt);
    return encoded ?? bytes;
  }

  static String _sanitizeStylesXml(String xml) {
    final numFmtsBlockRegex = RegExp(r'<numFmts\b[^>]*>[\s\S]*?</numFmts>');
    final numFmtTagRegex = RegExp(r'<numFmt\b[^>]*/>');
    final numFmtIdRegex = RegExp(r'numFmtId="(\d+)"');
    final xfTagRegex = RegExp(r'<xf\b[^>]*>');

    var nextCustomId = 164;
    final usedCustomIds = <int>{};
    final remap = <int, int>{};
    final declaredCustomIds = <int>{};

    var rewrittenXml = xml.replaceFirstMapped(numFmtsBlockRegex, (blockMatch) {
      final block = blockMatch.group(0)!;
      final tags = numFmtTagRegex.allMatches(block).map((m) => m.group(0)!).toList();
      if (tags.isEmpty) return block;

      final rewrittenTags = <String>[];
      for (final tag in tags) {
        final idMatch = numFmtIdRegex.firstMatch(tag);
        if (idMatch == null) {
          rewrittenTags.add(tag);
          continue;
        }

        final originalId = int.tryParse(idMatch.group(1)!);
        if (originalId == null) {
          rewrittenTags.add(tag);
          continue;
        }

        var finalId = originalId;
        if (originalId < 164 || usedCustomIds.contains(originalId)) {
          while (usedCustomIds.contains(nextCustomId)) {
            nextCustomId++;
          }
          finalId = nextCustomId;
          usedCustomIds.add(finalId);
          nextCustomId++;
        } else {
          usedCustomIds.add(originalId);
        }
        declaredCustomIds.add(finalId);
        remap[originalId] = finalId;

        if (finalId == originalId) {
          rewrittenTags.add(tag);
        } else {
          rewrittenTags.add(tag.replaceFirst('numFmtId="$originalId"', 'numFmtId="$finalId"'));
        }
      }

      final numFmtsOpenTagRegex = RegExp(r'<numFmts\b[^>]*>');
      final openTagMatch = numFmtsOpenTagRegex.firstMatch(block);
      final openTag = openTagMatch?.group(0) ?? '<numFmts>';
      final updatedOpenTag = openTag.contains('count=')
          ? openTag.replaceFirst(RegExp(r'count="\d+"'), 'count="${rewrittenTags.length}"')
          : openTag.replaceFirst('<numFmts', '<numFmts count="${rewrittenTags.length}"');

      return '$updatedOpenTag${rewrittenTags.join()}</numFmts>';
    });

    rewrittenXml = rewrittenXml.replaceAllMapped(xfTagRegex, (xfMatch) {
      final tag = xfMatch.group(0)!;
      final idMatch = numFmtIdRegex.firstMatch(tag);
      if (idMatch == null) return tag;

      final rawId = int.tryParse(idMatch.group(1)!);
      if (rawId == null) return tag;

      final remapped = remap[rawId];
      if (remapped != null) {
        return tag.replaceFirst('numFmtId="$rawId"', 'numFmtId="$remapped"');
      }

      final isPotentiallyCustom = rawId >= 164 || (rawId >= 50 && rawId < 164);
      if (isPotentiallyCustom && !declaredCustomIds.contains(rawId)) {
        // Fallback về General khi style tham chiếu numFmt không tồn tại.
        return tag.replaceFirst('numFmtId="$rawId"', 'numFmtId="0"');
      }

      return tag;
    });

    return rewrittenXml;
  }
}
