import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../models/product.dart';
import '../models/invoice.dart';
import '../models/purchase_order.dart';

class StorageService {
  static const String _productsBox = 'products';
  static const String _invoicesBox = 'invoices';
  static const String _purchaseOrdersKey = 'purchase_orders';
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

  // Purchase Orders
  static List<PurchaseOrder> getPurchaseOrders() {
    final box = _invoicesBoxRef;
    final list = box.get(_purchaseOrdersKey, defaultValue: <Map>[]) as List;
    return list
        .map((e) => PurchaseOrder.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  static Future<void> savePurchaseOrder(PurchaseOrder order) async {
    final box = _invoicesBoxRef;
    final list = box.get(_purchaseOrdersKey, defaultValue: <Map>[]) as List;
    final maps = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    maps.add(order.toMap());
    await box.put(_purchaseOrdersKey, maps);
  }

  static Future<void> updatePurchaseOrder(PurchaseOrder order) async {
    final box = _invoicesBoxRef;
    final list = box.get(_purchaseOrdersKey, defaultValue: <Map>[]) as List;
    final maps = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final idx = maps.indexWhere((e) => (e['id'] ?? '').toString() == order.id);
    if (idx >= 0) {
      maps[idx] = order.toMap();
    } else {
      maps.add(order.toMap());
    }
    await box.put(_purchaseOrdersKey, maps);
  }

  static Future<void> deletePurchaseOrder(String orderId) async {
    final box = _invoicesBoxRef;
    final list = box.get(_purchaseOrdersKey, defaultValue: <Map>[]) as List;
    final maps = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    maps.removeWhere((e) => (e['id'] ?? '').toString() == orderId);
    await box.put(_purchaseOrdersKey, maps);
  }

  static Future<void> applyPurchaseOrderInventory(PurchaseOrder order) async {
    if (order.items.isEmpty) return;
    final products = getProducts();
    final productById = <String, Product>{for (final p in products) p.id: p};
    final productByCode = <String, Product>{
      for (final p in products) _normalizeCode(p.code): p,
    };

    var changed = false;
    for (final item in order.items) {
      Product? product;
      if (item.productId.trim().isNotEmpty) {
        product = productById[item.productId];
      }
      product ??= productByCode[_normalizeCode(item.productCode)];
      if (product == null) continue;

      product.stock = (product.stock + item.quantity).clamp(0, 999999);
      if (item.importPrice > 0) {
        product.costPrice = item.importPrice;
      }
      changed = true;
    }

    if (changed) {
      await saveProducts(products);
    }
  }

  static Future<void> rollbackPurchaseOrderInventory(PurchaseOrder order) async {
    if (order.items.isEmpty) return;
    final products = getProducts();
    final productById = <String, Product>{for (final p in products) p.id: p};
    final productByCode = <String, Product>{
      for (final p in products) _normalizeCode(p.code): p,
    };

    var changed = false;
    for (final item in order.items) {
      Product? product;
      if (item.productId.trim().isNotEmpty) {
        product = productById[item.productId];
      }
      product ??= productByCode[_normalizeCode(item.productCode)];
      if (product == null) continue;

      product.stock = (product.stock - item.quantity).clamp(0, 999999);
      changed = true;
    }

    if (changed) {
      await saveProducts(products);
    }
  }

  static String nextPurchaseOrderCode() {
    final orders = getPurchaseOrders();
    final maxNo = orders.fold<int>(0, (currentMax, order) {
      final match = RegExp(r'^PN(\d+)$').firstMatch(order.code);
      if (match == null) return currentMax;
      final parsed = int.tryParse(match.group(1) ?? '') ?? 0;
      return parsed > currentMax ? parsed : currentMax;
    });
    final next = maxNo + 1;
    return 'PN${next.toString().padLeft(6, '0')}';
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
