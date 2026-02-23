class SaleItem {
  final String productId;
  final String productName;
  final String productCode;
  double price;
  int quantity;
  double get total => price * quantity;

  SaleItem({
    required this.productId,
    required this.productName,
    required this.productCode,
    required this.price,
    required this.quantity,
  });

  Map<String, dynamic> toMap() {
    return {
      'productId': productId,
      'productName': productName,
      'productCode': productCode,
      'price': price,
      'quantity': quantity,
    };
  }

  factory SaleItem.fromMap(Map<String, dynamic> map) {
    return SaleItem(
      productId: map['productId'] as String,
      productName: map['productName'] as String,
      productCode: map['productCode'] as String,
      price: (map['price'] as num).toDouble(),
      quantity: map['quantity'] as int,
    );
  }

  SaleItem copyWith({double? price, int? quantity}) {
    return SaleItem(
      productId: productId,
      productName: productName,
      productCode: productCode,
      price: price ?? this.price,
      quantity: quantity ?? this.quantity,
    );
  }
}
