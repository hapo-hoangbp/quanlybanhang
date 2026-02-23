import 'dart:io';

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
    );

    if (result == null || result.files.isEmpty) {
      return ExcelImportResult(products: [], error: 'Chưa chọn file');
    }

    final path = result.files.single.path;
    if (path == null || path.isEmpty) {
      return ExcelImportResult(products: [], error: 'Không đọc được đường dẫn file');
    }

    return importFromPath(path);
  }

  static Future<ExcelImportResult> importFromPath(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      final sheet = excel.tables.keys.isNotEmpty ? excel.tables[excel.tables.keys.first]! : null;
      if (sheet == null || sheet.rows.isEmpty) {
        return ExcelImportResult(products: [], error: 'File Excel trống');
      }

      int nameCol = -1;
      int codeCol = -1;
      int barcodeCol = -1;
      int priceCol = -1;
      int stockCol = -1;
      int unitCol = -1;
      int dataStartRow = 0;

      final firstRow = sheet.rows.isNotEmpty ? sheet.rows[0] : <Data?>[];
      final headerTexts = firstRow.map((c) => _cellValue(c)?.toString().toLowerCase().trim() ?? '').toList();

      // Ánh xạ theo cột KiotViet: Loại hàng, Nhóm hàng, Mã hàng, Mã vạch, Tên hàng, ...
      final nameKeywords = ['tên hàng', 'ten hang', 'tên sp', 'tên sản phẩm', 'sản phẩm', 'san pham'];
      final codeKeywords = ['mã hàng', 'ma hang', 'mã sp', 'mã sản phẩm', 'code', 'sku'];
      final barcodeKeywords = ['mã vạch', 'ma vach', 'barcode'];
      final priceKeywords = ['giá bán', 'gia ban', 'đơn giá', 'don gia', 'giá', 'gia'];
      final stockKeywords = ['tồn kho', 'ton kho', 'tồn', 'ton'];
      final unitKeywords = ['đvt', 'dvt', 'đơn vị', 'don vi', 'đơn vị tính'];

      for (var i = 0; i < headerTexts.length; i++) {
        final h = headerTexts[i];
        if (nameCol < 0 && nameKeywords.any((k) => h.contains(k))) nameCol = i;
        if (codeCol < 0 && codeKeywords.any((k) => h.contains(k))) codeCol = i;
        if (barcodeCol < 0 && barcodeKeywords.any((k) => h.contains(k))) barcodeCol = i;
        if (priceCol < 0 && priceKeywords.any((k) => h.contains(k))) priceCol = i;
        if (stockCol < 0 && stockKeywords.any((k) => h.contains(k))) stockCol = i;
        if (unitCol < 0 && unitKeywords.any((k) => h.contains(k))) unitCol = i;
      }

      if (nameCol < 0 || priceCol < 0) {
        nameCol = nameCol >= 0 ? nameCol : 4;
        codeCol = codeCol >= 0 ? codeCol : 2;
        priceCol = priceCol >= 0 ? priceCol : 6;
        dataStartRow = 0;
      } else {
        dataStartRow = 1;
      }

      final products = <Product>[];
      var skipped = 0;
      final existingCodes = <String>{};

      for (var r = dataStartRow; r < sheet.rows.length; r++) {
        final row = sheet.rows[r];
        final name = _cellValue(nameCol < row.length ? row[nameCol] : null)?.toString().trim();
        var code = _cellValue(codeCol >= 0 && codeCol < row.length ? row[codeCol] : null)?.toString().trim() ?? '';
        final barcode = _cellValue(barcodeCol >= 0 && barcodeCol < row.length ? row[barcodeCol] : null)?.toString().trim() ?? '';
        final priceRaw = _cellValue(priceCol < row.length ? row[priceCol] : null);
        final stockRaw = stockCol >= 0 && stockCol < row.length ? _cellValue(row[stockCol]) : null;
        final unitRaw = unitCol >= 0 && unitCol < row.length ? _cellValue(row[unitCol]) : null;

        if (name == null || (name.isEmpty && code.isEmpty && barcode.isEmpty)) {
          skipped++;
          continue;
        }

        final price = _parsePrice(priceRaw);
        if (price == null || price < 0) {
          skipped++;
          continue;
        }

        if (code.isEmpty && barcode.isNotEmpty) code = barcode;
        if (code.isEmpty) code = 'SP${(r - dataStartRow + 1).toString().padLeft(4, '0')}';
        var uniqueCode = code;
        var suffix = 1;
        while (existingCodes.contains(uniqueCode)) {
          uniqueCode = '$code-$suffix';
          suffix++;
        }
        existingCodes.add(uniqueCode);

        final stock = _parseInt(stockRaw) ?? 0;
        final unit = (unitRaw?.toString().trim().isNotEmpty == true) ? unitRaw.toString().trim() : 'cái';

        products.add(Product(
          id: const Uuid().v4(),
          name: name,
          code: uniqueCode,
          price: price,
          stock: stock,
          unit: unit,
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
      TextCellValue() => v.value.text ?? v.toString(),
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
}
