/// Format số thành chuỗi VNĐ có dấu phân cách (VD: 150.000)
String formatVndPrice(num? value) {
  if (value == null || value < 0) return '';
  final s = value.toInt().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// Chuyển chuỗi giá VNĐ sang số.
/// Hỗ trợ: 15000, 15.000, 15,000
double? parseVndPrice(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final s = value.trim().replaceAll(',', '').replaceAll('.', '').replaceAll(RegExp(r'\s'), '');
  return double.tryParse(s);
}

/// Validate giá VNĐ, trả về thông báo lỗi hoặc null nếu hợp lệ.
String? validateVndPrice(String? value, {String fieldName = 'Giá', bool required = true}) {
  if (value == null || value.trim().isEmpty) return required ? 'Nhập $fieldName' : null;
  final price = parseVndPrice(value);
  if (price == null) return '$fieldName không hợp lệ (VD: 15.000 hoặc 15000)';
  if (price < 0) return '$fieldName phải >= 0';
  return null;
}
