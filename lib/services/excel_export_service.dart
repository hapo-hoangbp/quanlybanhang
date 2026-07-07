import 'dart:io';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../models/product.dart';

class ExcelExportService {
  static Future<String?> exportProducts(List<Product> products) async {
    final excel = Excel.createExcel();
    final sheet = excel['Danh sách hàng hoá'];

    sheet.appendRow([
      TextCellValue('Mã hàng'),
      TextCellValue('Tên hàng'),
      TextCellValue('Giá bán'),
      TextCellValue('Giá vốn'),
      TextCellValue('Tồn kho'),
      TextCellValue('Đơn vị'),
    ]);

    for (final p in products) {
      sheet.appendRow([
        TextCellValue(p.code),
        TextCellValue(p.name),
        IntCellValue(p.price.round()),
        IntCellValue(p.costPrice.round()),
        IntCellValue(p.stock),
        TextCellValue(p.unit),
      ]);
    }

    final fileBytes = excel.encode();
    if (fileBytes == null) return 'Không thể tạo file Excel';

    final outputPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Xuất danh sách hàng hoá',
      fileName: 'hang_hoa_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx',
      allowedExtensions: ['xlsx'],
      type: FileType.custom,
    );

    if (outputPath == null) return null;

    try {
      await File(outputPath).writeAsBytes(fileBytes);
      return null;
    } catch (e) {
      return 'Lỗi ghi file: $e';
    }
  }
}
