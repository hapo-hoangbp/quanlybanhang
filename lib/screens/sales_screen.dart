import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/product.dart';
import '../models/sale_item.dart';
import '../models/invoice.dart';
import '../services/storage_service.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  final List<SaleItem> _cart = [];
  final _searchController = TextEditingController();
  List<Product> _products = [];
  List<Product> _filteredProducts = [];
  double _discountAmount = 0;
  final _formatCurrency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫');

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _searchController.addListener(_filterProducts);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadProducts() {
    setState(() {
      _products = StorageService.getProducts();
      _filterProducts();
    });
  }

  void _filterProducts() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        _filteredProducts = List.from(_products);
      } else {
        _filteredProducts = _products.where((p) {
          return p.name.toLowerCase().contains(query) ||
              p.code.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  double get _subtotal =>
      _cart.fold(0, (sum, item) => sum + item.total);

  double get _total => (_subtotal - _discountAmount).clamp(0, double.infinity);

  void _addToCart(Product product) {
    setState(() {
      final existing = _cart.where((i) => i.productId == product.id).firstOrNull;
      if (existing != null) {
        if (existing.quantity < product.stock) {
          final idx = _cart.indexOf(existing);
          _cart[idx] = existing.copyWith(quantity: existing.quantity + 1);
        }
      } else {
        _cart.add(SaleItem(
          productId: product.id,
          productName: product.name,
          productCode: product.code,
          price: product.price,
          quantity: 1,
        ));
      }
    });
  }

  void _updateCartItem(SaleItem item, int newQty) {
    if (newQty <= 0) {
      setState(() => _cart.removeWhere((i) => i.productId == item.productId));
      return;
    }
    final product = StorageService.getProductById(item.productId);
    final maxQty = product?.stock ?? 999;
    final qty = newQty.clamp(1, maxQty);
    setState(() {
      final idx = _cart.indexWhere((i) => i.productId == item.productId);
      if (idx >= 0) _cart[idx] = item.copyWith(quantity: qty);
    });
  }

  void _updateCartItemPrice(SaleItem item, double newPrice) {
    setState(() {
      final idx = _cart.indexWhere((i) => i.productId == item.productId);
      if (idx >= 0) _cart[idx] = item.copyWith(price: newPrice);
    });
  }

  void _removeFromCart(SaleItem item) {
    setState(() => _cart.removeWhere((i) => i.productId == item.productId));
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Giỏ hàng trống')),
      );
      return;
    }

    final items = List<SaleItem>.from(_cart);
    final invoice = Invoice(
      id: const Uuid().v4(),
      items: items,
      subtotal: _subtotal,
      discountAmount: _discountAmount,
      total: _total,
      createdAt: DateTime.now(),
    );

    for (final item in items) {
      await StorageService.updateProductStock(item.productId, item.quantity);
    }
    await StorageService.saveInvoice(invoice);

    setState(() {
      _cart.clear();
      _discountAmount = 0;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Thanh toán thành công: ${_formatCurrency.format(invoice.total)}'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _showDiscountDialog() {
    final controller = TextEditingController(
      text: _discountAmount.toStringAsFixed(0),
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nhập số tiền giảm'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Số tiền giảm (VNĐ)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () {
              final val = double.tryParse(controller.text) ?? 0;
              setState(() => _discountAmount = val.clamp(0, _subtotal));
              Navigator.pop(ctx);
            },
            child: const Text('Áp dụng'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bán hàng'),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Tìm kiếm tên hoặc mã sản phẩm...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                    ),
                  ),
                ),
                Expanded(
                  child: _filteredProducts.isEmpty
                      ? Center(
                          child: Text(
                            _products.isEmpty
                                ? 'Chưa có sản phẩm. Thêm ở màn hình Hàng hoá.'
                                : 'Không tìm thấy sản phẩm',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            childAspectRatio: 1.2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: _filteredProducts.length,
                          itemBuilder: (context, index) {
                            final p = _filteredProducts[index];
                            return _ProductCard(
                              product: p,
                              onTap: () => _addToCart(p),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            color: Colors.grey[300],
          ),
          Expanded(
            flex: 2,
            child: Container(
              color: const Color(0xFFF5F5F5),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(Icons.shopping_cart),
                        const SizedBox(width: 8),
                        Text(
                          'Giỏ hàng (${_cart.length})',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _cart.isEmpty
                        ? Center(
                            child: Text(
                              'Chưa có sản phẩm trong giỏ',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: _cart.length,
                            itemBuilder: (context, index) {
                              final item = _cart[index];
                              return _CartItemCard(
                                item: item,
                                onQtyChanged: (qty) =>
                                    _updateCartItem(item, qty),
                                onPriceChanged: (price) =>
                                    _updateCartItemPrice(item, price),
                                onRemove: () => _removeFromCart(item),
                                formatCurrency: _formatCurrency,
                              );
                            },
                          ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 8,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        _SummaryRow('Tạm tính:', _formatCurrency.format(_subtotal)),
                        InkWell(
                          onTap: _subtotal > 0 ? _showDiscountDialog : null,
                          child: _SummaryRow(
                            'Giảm giá:',
                            '- ${_formatCurrency.format(_discountAmount)}',
                            highlight: _discountAmount > 0,
                          ),
                        ),
                        const Divider(height: 24),
                        _SummaryRow(
                          'TỔNG CỘNG:',
                          _formatCurrency.format(_total),
                          bold: true,
                          total: true,
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _cart.isEmpty ? null : _checkout,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF1565C0),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: const Text('THANH TOÁN'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  const _ProductCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final format = NumberFormat.currency(locale: 'vi_VN', symbol: '₫');
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.shopping_bag, size: 40, color: Color(0xFF1565C0)),
              const SizedBox(height: 8),
              Text(
                product.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                format.format(product.price),
                style: const TextStyle(
                  color: Color(0xFF1565C0),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartItemCard extends StatelessWidget {
  final SaleItem item;
  final void Function(int) onQtyChanged;
  final void Function(double) onPriceChanged;
  final VoidCallback onRemove;
  final NumberFormat formatCurrency;

  const _CartItemCard({
    required this.item,
    required this.onQtyChanged,
    required this.onPriceChanged,
    required this.onRemove,
    required this.formatCurrency,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.productName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: onRemove,
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.all(4),
                    minimumSize: Size.zero,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Số lượng: '),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                  onPressed: () => onQtyChanged(item.quantity - 1),
                  style: IconButton.styleFrom(padding: EdgeInsets.zero),
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    '${item.quantity}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                  onPressed: () => onQtyChanged(item.quantity + 1),
                  style: IconButton.styleFrom(padding: EdgeInsets.zero),
                ),
              ],
            ),
            const SizedBox(height: 4),
            InkWell(
              onTap: () {
                final controller = TextEditingController(
                  text: item.price.toStringAsFixed(0),
                );
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Sửa giá'),
                    content: TextField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Giá (VNĐ)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Hủy'),
                      ),
                      FilledButton(
                        onPressed: () {
                          final val = double.tryParse(controller.text) ?? item.price;
                          onPriceChanged(val);
                          Navigator.pop(ctx);
                        },
                        child: const Text('Lưu'),
                      ),
                    ],
                  ),
                );
              },
              child: Row(
                children: [
                  const Icon(Icons.edit, size: 16, color: Colors.blue),
                  const SizedBox(width: 4),
                  Text(
                    formatCurrency.format(item.price),
                    style: const TextStyle(color: Colors.blue),
                  ),
                ],
              ),
            ),
            const Divider(height: 16),
            Text(
              'Thành tiền: ${formatCurrency.format(item.total)}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF1565C0),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final bool total;
  final bool highlight;

  const _SummaryRow(
    this.label,
    this.value, {
    this.bold = false,
    this.total = false,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : null,
              fontSize: total ? 18 : 14,
              color: highlight ? Colors.orange : null,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : null,
              fontSize: total ? 20 : 14,
              color: total ? const Color(0xFF1565C0) : null,
            ),
          ),
        ],
      ),
    );
  }
}
