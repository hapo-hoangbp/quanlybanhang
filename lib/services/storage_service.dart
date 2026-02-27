import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../models/product.dart';
import '../models/invoice.dart';

class StorageService {
  static const String _productsBox = 'products';
  static const String _invoicesBox = 'invoices';

  static Box? _productsBoxInstance;
  static Box? _invoicesBoxInstance;

  static Future<void> init() async {
    if (_productsBoxInstance != null && _invoicesBoxInstance != null) return;

    if (Platform.isAndroid || Platform.isIOS) {
      await Hive.initFlutter();
    } else {
      final dir = await getApplicationDocumentsDirectory();
      Hive.init(dir.path);
    }

    _productsBoxInstance = await _openBoxWithRetry(_productsBox);
    _invoicesBoxInstance = await _openBoxWithRetry(_invoicesBox);
  }

  static Future<Box> _openBoxWithRetry(String name) async {
    if (Hive.isBoxOpen(name)) {
      return Hive.box(name);
    }

    const maxAttempts = 6;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await Hive.openBox(name);
      } catch (e) {
        final isLockError = e is FileSystemException &&
            e.osError?.errorCode == 35;
        if (!isLockError || attempt == maxAttempts) {
          rethrow;
        }
        await Future.delayed(Duration(milliseconds: 250 * attempt));
      }
    }
    throw StateError('Không mở được Hive box: $name');
  }

  static Box get _productsBoxRef =>
      _productsBoxInstance ?? Hive.box(_productsBox);

  static Box get _invoicesBoxRef => _invoicesBoxInstance ?? Hive.box(_invoicesBox);

  // Products
  static List<Product> getProducts() {
    final box = _productsBoxRef;
    final list = box.get('list', defaultValue: <Map>[]) as List;
    return list
        .map((e) => Product.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<void> saveProducts(List<Product> products) async {
    final box = _productsBoxRef;
    await box.put(
      'list',
      products.map((e) => e.toMap()).toList(),
    );
  }

  static Future<void> addProduct(Product product) async {
    final products = getProducts();
    products.add(product);
    await saveProducts(products);
  }

  static Future<void> updateProduct(Product product) async {
    final products = getProducts();
    final index = products.indexWhere((p) => p.id == product.id);
    if (index >= 0) {
      products[index] = product;
      await saveProducts(products);
    }
  }

  static Future<void> deleteProduct(String id) async {
    final products = getProducts().where((p) => p.id != id).toList();
    await saveProducts(products);
  }

  static Product? getProductById(String id) {
    return getProducts().where((p) => p.id == id).firstOrNull;
  }

  // Invoices
  static List<Invoice> getInvoices() {
    final box = _invoicesBoxRef;
    final list = box.get('list', defaultValue: <Map>[]) as List;
    return list
        .map((e) => Invoice.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  static Future<void> saveInvoice(Invoice invoice) async {
    final box = _invoicesBoxRef;
    final list = box.get('list', defaultValue: <Map>[]) as List;
    final maps = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    maps.add(invoice.toMap());
    await box.put('list', maps);
  }

  static Future<void> updateProductStock(String productId, int quantitySold) async {
    final product = getProductById(productId);
    if (product != null) {
      product.stock = (product.stock - quantitySold).clamp(0, 999999);
      await updateProduct(product);
    }
  }
}
