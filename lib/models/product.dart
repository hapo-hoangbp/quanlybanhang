class Product {
  final String id;
  String name;
  String code;
  double price;
  int stock;
  String unit;

  Product({
    required this.id,
    required this.name,
    required this.code,
    required this.price,
    this.stock = 0,
    this.unit = 'cái',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'code': code,
      'price': price,
      'stock': stock,
      'unit': unit,
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'] as String,
      name: map['name'] as String,
      code: map['code'] as String,
      price: (map['price'] as num).toDouble(),
      stock: map['stock'] as int? ?? 0,
      unit: map['unit'] as String? ?? 'cái',
    );
  }
}
