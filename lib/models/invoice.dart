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
      total: (map['total'] as num).toDouble(),
      createdAt: DateTime.tryParse((map['createdAt'] ?? '').toString()) ?? DateTime.now(),
      note: map['note'] as String?,
    );
  }
}
