import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../models/product.dart';
import '../models/invoice.dart';

class StorageService {
  static const String _productsBox = 'products';
  static const String _invoicesBox = 'invoices';
  static const String _bankQrProfilesKey = 'bank_qr_profiles';
  static const String _defaultBankQrIdKey = 'default_bank_qr_id';

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

  static Future<ProductUpsertResult> upsertProductsByCode(List<Product> incoming) async {
    final products = getProducts();
    final codeToIndex = <String, int>{};
    for (var i = 0; i < products.length; i++) {
      final key = _normalizeCode(products[i].code);
      if (key.isEmpty) continue;
      codeToIndex.putIfAbsent(key, () => i);
    }

    var inserted = 0;
    var updated = 0;

    for (final item in incoming) {
      final key = _normalizeCode(item.code);
      final existingIndex = key.isEmpty ? null : codeToIndex[key];
      if (existingIndex == null) {
        products.add(item);
        if (key.isNotEmpty) {
          codeToIndex[key] = products.length - 1;
        }
        inserted++;
        continue;
      }

      final current = products[existingIndex];
      products[existingIndex] = Product(
        id: current.id,
        name: item.name,
        code: item.code,
        price: item.price,
        costPrice: item.costPrice,
        stock: item.stock,
        unit: item.unit,
        imagePath: (item.imagePath != null && item.imagePath!.trim().isNotEmpty) ? item.imagePath : current.imagePath,
      );
      updated++;
    }

    await saveProducts(products);
    return ProductUpsertResult(inserted: inserted, updated: updated);
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

  // Bank QR profiles
  static List<Map<String, dynamic>> getBankQrProfiles() {
    final box = _productsBoxRef;
    final list = box.get(_bankQrProfilesKey, defaultValue: <Map>[]) as List;
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<void> saveBankQrProfiles(List<Map<String, dynamic>> profiles) async {
    final box = _productsBoxRef;
    await box.put(_bankQrProfilesKey, profiles);
  }

  static String? getDefaultBankQrId() {
    final box = _productsBoxRef;
    final value = box.get(_defaultBankQrIdKey);
    if (value is String && value.trim().isNotEmpty) return value;
    return null;
  }

  static Future<void> setDefaultBankQrId(String? id) async {
    final box = _productsBoxRef;
    if (id == null || id.trim().isEmpty) {
      await box.delete(_defaultBankQrIdKey);
      return;
    }
    await box.put(_defaultBankQrIdKey, id.trim());
  }

  static String _normalizeCode(String value) {
    return value.trim().toLowerCase();
  }
}

class ProductUpsertResult {
  final int inserted;
  final int updated;

  const ProductUpsertResult({
    required this.inserted,
    required this.updated,
  });
}
