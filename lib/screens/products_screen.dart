import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../services/storage_service.dart';
import '../services/excel_import_service.dart';
import 'product_form_screen.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  List<Product> _products = [];
  final _formatCurrency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫');

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  void _loadProducts() {
    setState(() {
      _products = StorageService.getProducts();
    });
  }

  Future<void> _importFromExcel() async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await ExcelImportService.pickAndImport();
    if (!mounted) return;
    if (result.error != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(result.error!), backgroundColor: Colors.red),
      );
      return;
    }
    if (result.products.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Không có dữ liệu hợp lệ để import')),
      );
      return;
    }
    for (final p in result.products) {
      await StorageService.addProduct(p);
    }
    _loadProducts();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Đã import ${result.products.length} sản phẩm${result.skipped > 0 ? ' (bỏ qua ${result.skipped} dòng)' : ''}',
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _deleteProduct(Product product) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa sản phẩm'),
        content: Text(
          'Bạn có chắc muốn xóa "${product.name}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await StorageService.deleteProduct(product.id);
      _loadProducts();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý hàng hoá'),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: 'Import Excel',
            onPressed: () async {
              _importFromExcel();
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (ctx) => const ProductFormScreen(),
                ),
              );
              _loadProducts();
            },
          ),
        ],
      ),
      body: _products.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 80,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Chưa có sản phẩm nào',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: _importFromExcel,
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Import Excel'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                        ),
                      ),
                      const SizedBox(width: 16),
                      FilledButton.icon(
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (ctx) => const ProductFormScreen(),
                            ),
                          );
                          _loadProducts();
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Thêm sản phẩm'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () async => _loadProducts(),
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _products.length,
                itemBuilder: (context, index) {
                  final product = _products[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 2,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF2E7D32).withOpacity(0.2),
                        child: const Icon(
                          Icons.shopping_bag,
                          color: Color(0xFF2E7D32),
                        ),
                      ),
                      title: Text(
                        product.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text('Mã: ${product.code} | Tồn: ${product.stock} ${product.unit}'),
                          Text(
                            _formatCurrency.format(product.price),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2E7D32),
                            ),
                          ),
                        ],
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) async {
                          if (value == 'edit') {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (ctx) => ProductFormScreen(
                                  product: product,
                                ),
                              ),
                            );
                            _loadProducts();
                          } else if (value == 'delete') {
                            _deleteProduct(product);
                          }
                        },
                        itemBuilder: (ctx) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit),
                                SizedBox(width: 8),
                                Text('Chỉnh sửa'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, color: Colors.red),
                                SizedBox(width: 8),
                                Text('Xóa', style: TextStyle(color: Colors.red)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (ctx) => ProductFormScreen(
                              product: product,
                            ),
                          ),
                        );
                        _loadProducts();
                      },
                    ),
                  );
                },
              ),
            ),
    );
  }
}
