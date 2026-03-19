import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/purchase_order.dart';
import '../models/sale_item.dart';
import 'storage_service.dart';

class PrintService {
  static final _fmt = NumberFormat('#,###', 'vi_VN');
  static final _dateFmt = DateFormat('dd/MM/yyyy HH:mm');
  static const String defaultShopPhone = '0374.72.1993';
  static const String defaultShopAddress = 'Dịch vụ Chính Vân';

  /// Giấy K80 nhưng vùng in thực tế của đa số máy chỉ khoảng 72mm.
  /// Dùng chiều rộng hữu dụng để tránh tràn/cắt cột số tiền bên phải.
  static const double k80WidthPt = 204.09; // 72mm printable width
  static const double kMarginPt = 6;
  static const double kTrailingLinesPt = 36; // 3 dòng trắng cuối (~12pt/dòng)

  static PdfPageFormat get pageFormatK80 => PdfPageFormat(
        k80WidthPt,
        double.infinity, // chiều dài theo nội dung
        marginLeft: kMarginPt,
        marginRight: kMarginPt,
        marginTop: kMarginPt,
        marginBottom: kMarginPt,
      );

  /// Mở hộp thoại in hệ thống (giống Ctrl+P) với PDF hóa đơn.
  static Future<void> printInvoice({
    required BuildContext context,
    required List<SaleItem> items,
    required double subtotal,
    required double discountAmount,
    required double total,
    String? invoiceId,
    DateTime? createdAt,
    String? customerName,
    String shopName = 'Tạp Hoá Hoàng Dung',
    String shopPhone = defaultShopPhone,
    String shopAddress = defaultShopAddress,
    String? paymentQrData,
    String? paymentQrLabel,
    String? paymentQrImageUrl,
  }) async {
    final resolvedQr = _resolvePaymentQr(
      total: total,
      paymentQrData: paymentQrData,
      paymentQrLabel: paymentQrLabel,
      paymentQrImageUrl: paymentQrImageUrl,
    );
    await Printing.layoutPdf(
      name: 'Hoa_don_${invoiceId ?? ''}',
      onLayout: (_) async => _buildPdf(
        items: items,
        subtotal: subtotal,
        discountAmount: discountAmount,
        total: total,
        invoiceId: invoiceId,
        createdAt: createdAt ?? DateTime.now(),
        customerName: customerName,
        shopName: shopName,
        shopPhone: shopPhone,
        shopAddress: shopAddress,
        paymentQrData: resolvedQr.$1,
        paymentQrLabel: resolvedQr.$2,
        paymentQrImageUrl: resolvedQr.$3,
      ),
    );
  }

  static Future<void> printPurchaseOrderA5({
    required BuildContext context,
    required PurchaseOrder order,
    String branchName = 'Chi nhánh trung tâm',
    String creatorName = 'Quản trị',
    String supplierAddress = '',
  }) async {
    await Printing.layoutPdf(
      name: 'Phieu_nhap_${order.code}',
      onLayout: (_) async => _buildPurchaseOrderA5Pdf(
        order: order,
        branchName: branchName,
        creatorName: creatorName,
        supplierAddress: supplierAddress,
      ),
    );
  }

  static (String?, String?, String?) _resolvePaymentQr({
    required double total,
    String? paymentQrData,
    String? paymentQrLabel,
    String? paymentQrImageUrl,
  }) {
    final directData = paymentQrData?.trim() ?? '';
    final directImageUrl = paymentQrImageUrl?.trim() ?? '';
    if (directData.isNotEmpty) {
      return (directData, paymentQrLabel?.trim(), directImageUrl.isEmpty ? null : directImageUrl);
    }

    final profiles = StorageService.getBankQrProfiles();
    if (profiles.isEmpty) return (null, null, null);
    final defaultId = StorageService.getDefaultBankQrId();
    final selected = profiles.where((e) => (e['id'] ?? '').toString() == defaultId).firstOrNull;
    final fallback = selected ?? profiles.first;
    final bankCode = (fallback['bankCode'] ?? '').toString().trim();
    final accountNumber = (fallback['accountNumber'] ?? '').toString().trim();
    final label = (fallback['name'] ?? '').toString().trim();
    if (bankCode.isNotEmpty && accountNumber.isNotEmpty) {
      final amountValue = total.round().clamp(0, 999999999);
      final accountName = Uri.encodeComponent((fallback['accountName'] ?? '').toString().trim());
      final accountPart = accountName.isEmpty ? '' : '&accountName=$accountName';
      final imageUrl =
          'https://img.vietqr.io/image/$bankCode-$accountNumber-compact2.png?amount=$amountValue&addInfo=Thanh%20toan%20hoa%20don$accountPart';
      return (null, label.isEmpty ? null : label, imageUrl);
    }
    final template = (fallback['qrTemplate'] ?? '').toString().trim();
    if (template.isEmpty) return (null, null, null);
    final amountValue = total.round().clamp(0, 999999999);
    final qrData = template.replaceAll('{amount}', amountValue.toString());
    return (qrData, label.isEmpty ? null : label, null);
  }

  static Future<Uint8List> _buildPdf({
    required List<SaleItem> items,
    required double subtotal,
    required double discountAmount,
    required double total,
    String? invoiceId,
    required DateTime createdAt,
    String? customerName,
    required String shopName,
    required String shopPhone,
    required String shopAddress,
    String? paymentQrData,
    String? paymentQrLabel,
    String? paymentQrImageUrl,
  }) async {
    final doc = pw.Document();
    // Arial Unicode MS — font Unicode đầy đủ, hỗ trợ tiếng Việt
    final fontData = await rootBundle.load('assets/fonts/ArialUnicode.ttf');
    final font = pw.Font.ttf(fontData);
    final fontBold = font; // dùng chung, Arial Unicode chỉ có 1 weight
    pw.MemoryImage? paymentQrImage;
    if (paymentQrImageUrl != null && paymentQrImageUrl.trim().isNotEmpty) {
      try {
        final imageBytes = await NetworkAssetBundle(Uri.parse(paymentQrImageUrl.trim())).load(paymentQrImageUrl.trim());
        paymentQrImage = pw.MemoryImage(imageBytes.buffer.asUint8List());
      } catch (_) {
        paymentQrImage = null;
      }
    }

    doc.addPage(
      pw.Page(
        pageFormat: pageFormatK80,
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
              if (shopPhone.trim().isNotEmpty) ...[
                pw.Center(
                  child: pw.Text(
                    'SĐT: ${shopPhone.trim()}',
                    style: pw.TextStyle(font: font, fontSize: 8.5),
                  ),
                ),
                pw.SizedBox(height: 1),
              ],
              if (shopAddress.trim().isNotEmpty) ...[
                pw.Center(
                  child: pw.Text(
                    'Địa chỉ: ${shopAddress.trim()}',
                    style: pw.TextStyle(font: font, fontSize: 8.5),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.SizedBox(height: 2),
              ],
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
              if (customerName != null && customerName.trim().isNotEmpty) ...[
                pw.SizedBox(height: 1),
                pw.Center(
                  child: pw.Text(
                    'Khách: ${customerName.trim()}',
                    style: pw.TextStyle(font: font, fontSize: 8),
                    textAlign: pw.TextAlign.center,
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
                    width: 24,
                    child: pw.Text('SL', style: pw.TextStyle(font: fontBold, fontSize: 9), textAlign: pw.TextAlign.center),
                  ),
                  pw.SizedBox(
                    width: 44,
                    child: pw.Text('Đơn giá', style: pw.TextStyle(font: fontBold, fontSize: 9), textAlign: pw.TextAlign.right),
                  ),
                  pw.SizedBox(
                    width: 44,
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
                            width: 24,
                            child: pw.Text(
                              '${item.quantity}',
                              style: pw.TextStyle(font: font, fontSize: 9),
                              textAlign: pw.TextAlign.center,
                            ),
                          ),
                          pw.SizedBox(
                            width: 44,
                            child: pw.Text(
                              _fmt.format(item.price),
                              style: pw.TextStyle(font: font, fontSize: 9),
                              textAlign: pw.TextAlign.right,
                            ),
                          ),
                          pw.SizedBox(
                            width: 44,
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
              if (discountAmount > 0) _summaryRow('Giảm giá', '- ${_fmt.format(discountAmount)}', font: font, fontBold: font),
              pw.Divider(thickness: 0.5),
              _summaryRow('TỔNG THANH TOÁN', '${_fmt.format(total)} đ', font: fontBold, fontBold: fontBold, large: true),
              if ((paymentQrImage != null) || (paymentQrData != null && paymentQrData.trim().isNotEmpty)) ...[
                pw.SizedBox(height: 8),
                pw.Center(
                  child: pw.Text(
                    paymentQrLabel?.trim().isNotEmpty == true
                        ? 'Quét QR thanh toán (${paymentQrLabel!.trim()})'
                        : 'Quét QR thanh toán',
                    style: pw.TextStyle(font: fontBold, fontSize: 9),
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Center(
                  child: paymentQrImage != null
                      ? pw.Image(paymentQrImage, width: 100, height: 100)
                      : pw.BarcodeWidget(
                          barcode: pw.Barcode.qrCode(),
                          data: paymentQrData!.trim(),
                          width: 100,
                          height: 100,
                        ),
                ),
              ],

              pw.SizedBox(height: 12),
              pw.Center(
                child: pw.Text(
                  'Cảm ơn quý khách!',
                  style: pw.TextStyle(font: fontBold, fontSize: 11),
                ),
              ),
              pw.SizedBox(height: kTrailingLinesPt), // 3 dòng trắng cuối trước khi cắt giấy
            ],
          );
        },
      ),
    );

    return Uint8List.fromList(await doc.save());
  }

  static Future<Uint8List> _buildPurchaseOrderA5Pdf({
    required PurchaseOrder order,
    required String branchName,
    required String creatorName,
    required String supplierAddress,
  }) async {
    final doc = pw.Document();
    final fontData = await rootBundle.load('assets/fonts/ArialUnicode.ttf');
    final font = pw.Font.ttf(fontData);
    final fontBold = font;

    final qtyTotal = order.items.fold<int>(0, (sum, i) => sum + i.quantity);
    final subTotal = order.items.fold<double>(0.0, (sum, i) => sum + i.unitPrice * i.quantity);
    final totalDiscount = order.items.fold<double>(0.0, (sum, i) => sum + i.discountAmount * i.quantity);

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5.landscape,
        margin: const pw.EdgeInsets.fromLTRB(18, 14, 18, 14),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                _dateFmt.format(order.createdAt),
                style: pw.TextStyle(font: font, fontSize: 8),
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Center(
              child: pw.Text(
                'PHIẾU NHẬP HÀNG',
                style: pw.TextStyle(font: fontBold, fontSize: 16),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text(
                'Mã phiếu: ${order.code}',
                style: pw.TextStyle(font: fontBold, fontSize: 10),
              ),
            ),
            pw.Center(
              child: pw.Text(
                'Ngày: ${_dateFmt.format(order.createdAt)}',
                style: pw.TextStyle(font: font, fontSize: 9),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text('Chi nhánh nhập: $branchName', style: pw.TextStyle(font: font, fontSize: 10)),
            pw.Text('Người tạo: $creatorName', style: pw.TextStyle(font: font, fontSize: 10)),
            pw.Text('Nhà cung cấp: ${order.supplierName}', style: pw.TextStyle(font: font, fontSize: 10)),
            pw.Text('Địa chỉ: ${supplierAddress.trim().isEmpty ? '-' : supplierAddress}', style: pw.TextStyle(font: font, fontSize: 10)),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: const ['STT', 'Mã hàng', 'Tên hàng', 'Đơn giá', 'Số lượng', 'Chiết khấu', 'Thành tiền'],
              data: order.items.asMap().entries.map((entry) {
                final idx = entry.key + 1;
                final item = entry.value;
                return [
                  '$idx',
                  item.productCode,
                  item.productName,
                  _fmt.format(item.unitPrice),
                  '${item.quantity}',
                  _fmt.format(item.discountAmount),
                  _fmt.format(item.lineTotal),
                ];
              }).toList(),
              headerStyle: pw.TextStyle(font: fontBold, fontSize: 9),
              cellStyle: pw.TextStyle(font: font, fontSize: 9),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              border: pw.TableBorder.all(width: 0.6, color: PdfColors.black),
              columnWidths: {
                0: const pw.FixedColumnWidth(26),
                1: const pw.FixedColumnWidth(86),
                2: const pw.FlexColumnWidth(2.6),
                3: const pw.FixedColumnWidth(58),
                4: const pw.FixedColumnWidth(46),
                5: const pw.FixedColumnWidth(58),
                6: const pw.FixedColumnWidth(70),
              },
              cellAlignments: {
                0: pw.Alignment.center,
                3: pw.Alignment.centerRight,
                4: pw.Alignment.center,
                5: pw.Alignment.centerRight,
                6: pw.Alignment.centerRight,
              },
            ),
            pw.SizedBox(height: 8),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.SizedBox(
                width: 240,
                child: pw.Column(
                  children: [
                    _purchaseSummaryRow('Tổng số lượng hàng:', '$qtyTotal', font, fontBold),
                    _purchaseSummaryRow('Tổng tiền hàng:', _fmt.format(subTotal), font, fontBold),
                    _purchaseSummaryRow('Chiết khấu hóa đơn:', _fmt.format(totalDiscount), font, fontBold),
                    _purchaseSummaryRow('Tiền cần trả NCC:', _fmt.format(order.amountDue), fontBold, fontBold),
                  ],
                ),
              ),
            ),
            pw.Spacer(),
            pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Center(
                    child: pw.Text('Nhà cung cấp', style: pw.TextStyle(font: fontBold, fontSize: 11)),
                  ),
                ),
                pw.Expanded(
                  child: pw.Center(
                    child: pw.Text('Người lập', style: pw.TextStyle(font: fontBold, fontSize: 11)),
                  ),
                ),
              ],
            ),
          ],
        ),
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
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Text(label, style: pw.TextStyle(font: fontBold, fontSize: size)),
          ),
          pw.SizedBox(
            width: 54,
            child: pw.Text(
              value,
              style: pw.TextStyle(font: fontBold, fontSize: size),
              textAlign: pw.TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _purchaseSummaryRow(
    String label,
    String value,
    pw.Font labelFont,
    pw.Font valueFont,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              label,
              style: pw.TextStyle(font: labelFont, fontSize: 10),
              textAlign: pw.TextAlign.right,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.SizedBox(
            width: 66,
            child: pw.Text(
              value,
              style: pw.TextStyle(font: valueFont, fontSize: 10),
              textAlign: pw.TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
