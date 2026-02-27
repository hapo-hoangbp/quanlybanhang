import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/sale_item.dart';

class PrintService {
  static final _fmt = NumberFormat('#,###', 'vi_VN');
  static final _dateFmt = DateFormat('dd/MM/yyyy HH:mm');

  /// Mở hộp thoại in hệ thống (giống Ctrl+P) với PDF hóa đơn.
  static Future<void> printInvoice({
    required BuildContext context,
    required List<SaleItem> items,
    required double subtotal,
    required double discountAmount,
    required double total,
    String? invoiceId,
    DateTime? createdAt,
    String shopName = 'Quản lý tạp hoá',
  }) async {
    await Printing.layoutPdf(
      name: 'Hoa_don_${invoiceId ?? ''}',
      onLayout: (PdfPageFormat format) async {
        return _buildPdf(
          format: format,
          items: items,
          subtotal: subtotal,
          discountAmount: discountAmount,
          total: total,
          invoiceId: invoiceId,
          createdAt: createdAt ?? DateTime.now(),
          shopName: shopName,
        );
      },
    );
  }

  static Future<Uint8List> _buildPdf({
    required PdfPageFormat format,
    required List<SaleItem> items,
    required double subtotal,
    required double discountAmount,
    required double total,
    String? invoiceId,
    required DateTime createdAt,
    required String shopName,
  }) async {
    final doc = pw.Document();
    final font = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();

    // Giấy 80mm rộng
    final pageFormat = PdfPageFormat(
      format.width.clamp(0, 226.77), // 80mm = 226.77pt
      double.infinity,
      marginAll: 8,
    );

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // Header
              pw.Center(
                child: pw.Text(
                  shopName,
                  style: pw.TextStyle(font: fontBold, fontSize: 14),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(
                  'HÓA ĐƠN BÁN HÀNG',
                  style: pw.TextStyle(font: fontBold, fontSize: 12),
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Center(
                child: pw.Text(
                  _dateFmt.format(createdAt),
                  style: pw.TextStyle(font: font, fontSize: 9),
                ),
              ),
              if (invoiceId != null) ...[
                pw.SizedBox(height: 1),
                pw.Center(
                  child: pw.Text(
                    'Mã HĐ: ${invoiceId.substring(0, 8).toUpperCase()}',
                    style: pw.TextStyle(font: font, fontSize: 8),
                  ),
                ),
              ],
              pw.SizedBox(height: 6),
              pw.Divider(thickness: 0.5),

              // Header bảng
              pw.Row(
                children: [
                  pw.Expanded(
                    flex: 4,
                    child: pw.Text('Hàng hoá', style: pw.TextStyle(font: fontBold, fontSize: 9)),
                  ),
                  pw.SizedBox(
                    width: 28,
                    child: pw.Text('SL', style: pw.TextStyle(font: fontBold, fontSize: 9), textAlign: pw.TextAlign.center),
                  ),
                  pw.SizedBox(
                    width: 52,
                    child: pw.Text('Đơn giá', style: pw.TextStyle(font: fontBold, fontSize: 9), textAlign: pw.TextAlign.right),
                  ),
                  pw.SizedBox(
                    width: 52,
                    child: pw.Text('T.tiền', style: pw.TextStyle(font: fontBold, fontSize: 9), textAlign: pw.TextAlign.right),
                  ),
                ],
              ),
              pw.Divider(thickness: 0.5),

              // Danh sách mặt hàng
              ...items.where((i) => i.quantity > 0).map((item) {
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        item.productName,
                        style: pw.TextStyle(font: font, fontSize: 9),
                      ),
                      pw.Row(
                        children: [
                          pw.Expanded(flex: 4, child: pw.SizedBox()),
                          pw.SizedBox(
                            width: 28,
                            child: pw.Text(
                              '${item.quantity}',
                              style: pw.TextStyle(font: font, fontSize: 9),
                              textAlign: pw.TextAlign.center,
                            ),
                          ),
                          pw.SizedBox(
                            width: 52,
                            child: pw.Text(
                              _fmt.format(item.price),
                              style: pw.TextStyle(font: font, fontSize: 9),
                              textAlign: pw.TextAlign.right,
                            ),
                          ),
                          pw.SizedBox(
                            width: 52,
                            child: pw.Text(
                              _fmt.format(item.total),
                              style: pw.TextStyle(font: fontBold, fontSize: 9),
                              textAlign: pw.TextAlign.right,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),

              pw.Divider(thickness: 0.5),

              // Tổng cộng
              _summaryRow('Tổng tiền hàng', _fmt.format(subtotal), font: font, fontBold: font),
              if (discountAmount > 0)
                _summaryRow('Giảm giá', '- ${_fmt.format(discountAmount)}', font: font, fontBold: font),
              pw.Divider(thickness: 0.5),
              _summaryRow('TỔNG THANH TOÁN', '${_fmt.format(total)} đ', font: fontBold, fontBold: fontBold, large: true),

              pw.SizedBox(height: 12),
              pw.Center(
                child: pw.Text(
                  'Cảm ơn quý khách!',
                  style: pw.TextStyle(font: fontBold, fontSize: 11),
                ),
              ),
              pw.SizedBox(height: 4),
            ],
          );
        },
      ),
    );

    return Uint8List.fromList(await doc.save());
  }

  static pw.Widget _summaryRow(
    String label,
    String value, {
    required pw.Font font,
    required pw.Font fontBold,
    bool large = false,
  }) {
    final size = large ? 11.0 : 9.0;
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(font: fontBold, fontSize: size)),
          pw.Text(value, style: pw.TextStyle(font: fontBold, fontSize: size)),
        ],
      ),
    );
  }
}
