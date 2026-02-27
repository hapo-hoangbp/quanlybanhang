class Product {
  final String id;
  String name;
  String code;
  double price;
  double costPrice;
  int stock;
  String unit;
  String? imagePath;

  Product({
    required this.id,
    required this.name,
    required this.code,
    required this.price,
    this.costPrice = 0,
    this.stock = 0,
    this.unit = 'cái',
    this.imagePath,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'code': code,
      'price': price,
      'costPrice': costPrice,
      'stock': stock,
      'unit': unit,
      'imagePath': imagePath,
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'] as String,
      name: map['name'] as String,
      code: map['code'] as String,
      price: (map['price'] as num).toDouble(),
      costPrice: (map['costPrice'] as num?)?.toDouble() ?? 0,
      stock: map['stock'] as int? ?? 0,
      unit: map['unit'] as String? ?? 'cái',
      imagePath: map['imagePath'] as String?,
    );
  }
}
