import 'sale_item.dart';

class Invoice {
  final String id;
  final List<SaleItem> items;
  final double subtotal;
  final double discountAmount;
  final double total;
  final DateTime createdAt;
  final String? note;

  Invoice({
    required this.id,
    required this.items,
    required this.subtotal,
    this.discountAmount = 0,
    required this.total,
    required this.createdAt,
    this.note,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'items': items.map((e) => e.toMap()).toList(),
      'subtotal': subtotal,
      'discountAmount': discountAmount,
      'total': total,
      'createdAt': createdAt.toIso8601String(),
      'note': note,
    };
  }

  factory Invoice.fromMap(Map<String, dynamic> map) {
    return Invoice(
      id: map['id'] as String,
      items: (map['items'] as List)
          .map((e) => SaleItem.fromMap(e as Map<String, dynamic>))
          .toList(),
      subtotal: (map['subtotal'] as num).toDouble(),
      discountAmount: (map['discountAmount'] as num?)?.toDouble() ?? 0,
      total: (map['total'] as num).toDouble(),
      createdAt: DateTime.parse(map['createdAt'] as String),
      note: map['note'] as String?,
    );
  }
}
