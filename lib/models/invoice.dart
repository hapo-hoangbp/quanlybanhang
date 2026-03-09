import 'sale_item.dart';

class Invoice {
  final String id;
  final List<SaleItem> items;
  final double subtotal;
  final double discountAmount;
  final String discountType;
  final double discountValue;
  final double total;
  final DateTime createdAt;
  final String? customerName;
  final String? note;

  Invoice({
    required this.id,
    required this.items,
    required this.subtotal,
    this.discountAmount = 0,
    this.discountType = 'amount',
    this.discountValue = 0,
    required this.total,
    required this.createdAt,
    this.customerName,
    this.note,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'items': items.map((e) => e.toMap()).toList(),
      'subtotal': subtotal,
      'discountAmount': discountAmount,
      'discountType': discountType,
      'discountValue': discountValue,
      'total': total,
      'createdAt': createdAt.toIso8601String(),
      'customerName': customerName,
      'note': note,
    };
  }

  factory Invoice.fromMap(Map<String, dynamic> map) {
    final rawItems = map['items'];
    final itemsList = rawItems is List ? rawItems : const [];

    return Invoice(
      id: (map['id'] ?? '').toString(),
      items: itemsList
          .whereType<Map>()
          .map((e) => SaleItem.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      subtotal: (map['subtotal'] as num).toDouble(),
      discountAmount: (map['discountAmount'] as num?)?.toDouble() ?? 0,
      discountType: (map['discountType'] as String?) ?? 'amount',
      discountValue: (map['discountValue'] as num?)?.toDouble() ?? 0,
      total: (map['total'] as num).toDouble(),
      createdAt: DateTime.tryParse((map['createdAt'] ?? '').toString()) ?? DateTime.now(),
      customerName: map['customerName'] as String?,
      note: map['note'] as String?,
    );
  }
}
