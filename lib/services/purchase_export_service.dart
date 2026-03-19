import 'dart:io';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import '../models/purchase_order.dart';

class PurchaseExportService {
  static final DateFormat _dateFmt = DateFormat('dd/MM/yyyy HH:mm');

  static Future<String?> exportToExcel(List<PurchaseOrder> orders) async {
    final now = DateTime.now();
    final defaultFileName =
        'phieu_nhap_${DateFormat('yyyyMMdd_HHmmss').format(now)}.xlsx';
    final desktopPath = _desktopDirectoryPath();
    final finalPath = '$desktopPath/$defaultFileName';

    final excel = Excel.createExcel();
    final summarySheet = excel['DanhSachPhieuNhap'];
    final detailSheet = excel['ChiTietNhapHang'];

    _buildSummarySheet(summarySheet, orders);
    _buildDetailSheet(detailSheet, orders);

    final bytes = excel.encode();
    if (bytes == null) {
      throw Exception('Không thể tạo file Excel');
    }
    try {
      await File(finalPath).writeAsBytes(bytes, flush: true);
      return finalPath;
    } on FileSystemException catch (e) {
      throw Exception(
        'Không thể ghi file vào Desktop. '
        'Vui lòng cấp quyền Files and Folders -> Desktop cho ứng dụng, rồi thử lại.\n$e',
      );
    }
  }

  static String _desktopDirectoryPath() {
    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null && userProfile.isNotEmpty) {
        return '$userProfile\\Desktop';
      }
    }
    if (Platform.isMacOS || Platform.isLinux) {
      final user = Platform.environment['LOGNAME'] ?? Platform.environment['USER'];
      if (user != null && user.isNotEmpty) {
        return '/Users/$user/Desktop';
      }
    }
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return '$home/Desktop';
    }
    throw Exception('Không xác định được thư mục Desktop trên thiết bị này.');
  }

  static void _buildSummarySheet(Sheet sheet, List<PurchaseOrder> orders) {
    const headers = [
      'Mã nhập hàng',
      'Thời gian',
      'Mã NCC',
      'Nhà cung cấp',
      'Cần trả NCC',
      'Trạng thái',
      'Ghi chú',
    ];
    for (var c = 0; c < headers.length; c++) {
      sheet.updateCell(
        CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
        TextCellValue(headers[c]),
      );
    }

    for (var i = 0; i < orders.length; i++) {
      final o = orders[i];
      final row = i + 1;
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
          TextCellValue(o.code));
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row),
          TextCellValue(_dateFmt.format(o.createdAt)));
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row),
          TextCellValue(o.supplierCode));
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row),
          TextCellValue(o.supplierName));
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row),
          DoubleCellValue(o.amountDue));
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row),
          TextCellValue(o.status));
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row),
          TextCellValue(o.note ?? ''));
    }
  }

  static void _buildDetailSheet(Sheet sheet, List<PurchaseOrder> orders) {
    const headers = [
      'Mã nhập hàng',
      'Mã hàng',
      'Tên hàng',
      'Số lượng',
      'Đơn giá',
      'Giảm giá',
      'Giá nhập',
      'Thành tiền',
    ];
    for (var c = 0; c < headers.length; c++) {
      sheet.updateCell(
        CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
        TextCellValue(headers[c]),
      );
    }

    var row = 1;
    for (final order in orders) {
      for (final item in order.items) {
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
            TextCellValue(order.code));
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row),
            TextCellValue(item.productCode));
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row),
            TextCellValue(item.productName));
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row),
            IntCellValue(item.quantity));
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row),
            DoubleCellValue(item.unitPrice));
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row),
            DoubleCellValue(item.discountAmount));
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row),
            DoubleCellValue(item.importPrice));
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: row),
            DoubleCellValue(item.lineTotal));
        row++;
      }
    }
  }
}
