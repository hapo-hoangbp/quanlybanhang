class PurchaseOrderItem {
  final String productId;
  final String productCode;
  final String productName;
  final int quantity;
  final double unitPrice;
  final double discountAmount;

  const PurchaseOrderItem({
    required this.productId,
    required this.productCode,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    this.discountAmount = 0,
  });

  double get importPrice => (unitPrice - discountAmount).clamp(0, double.infinity).toDouble();
  double get lineTotal => importPrice * quantity;

  Map<String, dynamic> toMap() {
    return {
      'productId': productId,
      'productCode': productCode,
      'productName': productName,
      'quantity': quantity,
      'unitPrice': unitPrice,
      'discountAmount': discountAmount,
    };
  }

  factory PurchaseOrderItem.fromMap(Map<String, dynamic> map) {
    return PurchaseOrderItem(
      productId: (map['productId'] ?? '').toString(),
      productCode: (map['productCode'] ?? '').toString(),
      productName: (map['productName'] ?? '').toString(),
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
      unitPrice: (map['unitPrice'] as num?)?.toDouble() ?? 0,
      discountAmount: (map['discountAmount'] as num?)?.toDouble() ?? 0,
    );
  }
}

class PurchaseOrder {
  final String id;
  final String code;
  final String supplierCode;
  final String supplierName;
  final double amountDue;
  final String status;
  final DateTime createdAt;
  final String? note;
  final List<PurchaseOrderItem> items;

  PurchaseOrder({
    required this.id,
    required this.code,
    required this.supplierCode,
    required this.supplierName,
    required this.amountDue,
    required this.status,
    required this.createdAt,
    this.note,
    this.items = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'code': code,
      'supplierCode': supplierCode,
      'supplierName': supplierName,
      'amountDue': amountDue,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
      'note': note,
      'items': items.map((e) => e.toMap()).toList(),
    };
  }

  factory PurchaseOrder.fromMap(Map<String, dynamic> map) {
    return PurchaseOrder(
      id: (map['id'] ?? '').toString(),
      code: (map['code'] ?? '').toString(),
      supplierCode: (map['supplierCode'] ?? '').toString(),
      supplierName: (map['supplierName'] ?? '').toString(),
      amountDue: (map['amountDue'] as num?)?.toDouble() ?? 0,
      status: (map['status'] ?? 'Đã nhập hàng').toString(),
      createdAt: DateTime.tryParse((map['createdAt'] ?? '').toString()) ?? DateTime.now(),
      note: map['note'] as String?,
      items: ((map['items'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => PurchaseOrderItem.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}
