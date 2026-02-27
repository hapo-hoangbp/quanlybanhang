import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/product.dart';
import '../models/sale_item.dart';
import '../models/invoice.dart';
import '../services/storage_service.dart';
import '../utils/price_validator.dart';

class SalesScreen extends StatefulWidget {
  final bool isActive;

  const SalesScreen({super.key, this.isActive = true});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _InvoiceTabData {
  final String id;
  List<SaleItem> cart;
  double discountAmount;
  final TextEditingController tenderController;
  String paymentMethod;

  _InvoiceTabData({
    required this.id,
    List<SaleItem>? cart,
  })  : cart = cart ?? [],
        discountAmount = 0,
        tenderController = TextEditingController(),
        paymentMethod = 'cash';
}

class _SalesScreenState extends State<SalesScreen> {
  final _searchController = TextEditingController();
  final _customerSearchController = TextEditingController();
  final _tabScrollController = ScrollController();
  final _cartScrollKey = GlobalKey();
  bool _showSearchResults = true;
  final List<_InvoiceTabData> _tabs = [];
  int _activeTabIndex = 0;
  int _tabCounter = 1;
  List<Product> _products = [];
  List<Product> _filteredProducts = [];
  final _formatCurrency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫');
  final _formatCompact = NumberFormat('#,###', 'vi_VN');

  List<SaleItem> get _cart => _tabs.isNotEmpty ? _tabs[_activeTabIndex].cart : [];
  double get _discountAmount => _tabs.isNotEmpty ? _tabs[_activeTabIndex].discountAmount : 0;

  TextEditingController get _tenderController => _tabs.isNotEmpty ? _tabs[_activeTabIndex].tenderController : TextEditingController();
  String get _paymentMethod => _tabs.isNotEmpty ? _tabs[_activeTabIndex].paymentMethod : 'cash';
  set _paymentMethod(String v) {
    if (_tabs.isNotEmpty) _tabs[_activeTabIndex].paymentMethod = v;
  }

  @override
  void initState() {
    super.initState();
    _tabs.add(_InvoiceTabData(id: 'tab_1', cart: []));
    _loadProducts();
    _searchController.addListener(_filterProducts);
  }

  @override
  void didUpdateWidget(covariant SalesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _loadProducts();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _customerSearchController.dispose();
    _tabScrollController.dispose();
    for (final t in _tabs) {
      t.tenderController.dispose();
    }
    super.dispose();
  }

  void _addNewTab() {
    setState(() {
      _tabCounter++;
      _tabs.add(_InvoiceTabData(id: 'tab_$_tabCounter', cart: []));
      _activeTabIndex = _tabs.length - 1;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_tabScrollController.hasClients) {
        _tabScrollController.animateTo(
          _tabScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _closeTab(int index) async {
    if (_tabs.length <= 1) return;
    final tab = _tabs[index];
    final hasItems = tab.cart.isNotEmpty;
    final closed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Đóng hóa đơn'),
        content: Text(
          hasItems
              ? 'Hóa đơn ${index + 1} còn ${tab.cart.length} mặt hàng chưa thanh toán. Đóng hóa đơn sẽ xóa toàn bộ. Bạn có chắc?'
              : 'Bạn có chắc muốn đóng Hóa đơn ${index + 1}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
    if (closed != true || !mounted) return;
    setState(() {
      tab.tenderController.dispose();
      _tabs.removeAt(index);
      if (_activeTabIndex >= _tabs.length) _activeTabIndex = _tabs.length - 1;
      if (_activeTabIndex > index) _activeTabIndex--;
    });
  }

  void _switchTab(int index) {
    setState(() => _activeTabIndex = index);
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
        _filteredProducts = _products.where((p) => p.name.toLowerCase().contains(query) || p.code.toLowerCase().contains(query)).toList();
      }
    });
  }

  double get _subtotal => _cart.fold(0, (sum, item) => sum + item.total);
  double get _amountDue => (_subtotal - _discountAmount).clamp(0, double.infinity);
  bool get _hasPayableItems => _cart.any((i) => i.quantity > 0);
  int get _payableLinesCount => _cart.where((i) => i.quantity > 0).length;

  void _upsertCartItem(Product product, {int qty = 1}) {
    // Không phụ thuộc tồn kho: cho phép tăng số lượng tự do.
    const maxQty = 999999;
    final existing = _cart.where((i) => i.productId == product.id).firstOrNull;
    if (existing != null) {
      final requested = existing.quantity + qty;
      final newQty = requested.clamp(0, maxQty);

      final idx = _cart.indexOf(existing);
      _cart[idx] = existing.copyWith(quantity: newQty);
    } else {
      _cart.add(SaleItem(
        productId: product.id,
        productName: product.name,
        productCode: product.code,
        unit: product.unit,
        price: product.price,
        quantity: qty.clamp(0, maxQty),
      ));
    }
  }

  void _hideSearchResults() {
    if (!_showSearchResults) return;
    // Tránh cập nhật UI ngay trong lúc Flutter đang update mouse device.
    Future.microtask(() {
      if (!mounted) return;
      if (!_showSearchResults) return;
      setState(() => _showSearchResults = false);
    });
  }

  void _selectProductFromSearch(Product chosen) {
    Future.microtask(() {
      if (!mounted) return;
      setState(() {
        _upsertCartItem(chosen, qty: 1);
        _showSearchResults = false;
      });
    });
  }

  void _selectFirstResultOnEnter() {
    final q = _searchController.text.trim();
    if (q.isEmpty) return;

    final exact = _products.where((p) => p.code.toLowerCase() == q.toLowerCase()).firstOrNull;
    final chosen = exact ?? (_filteredProducts.isNotEmpty ? _filteredProducts.first : null);
    if (chosen == null) return;
    _selectProductFromSearch(chosen);
  }

  void _addBySearch() {
    _selectFirstResultOnEnter();
  }

  void _updateCartItem(SaleItem item, int newQty) {
    // Cho phép giảm về 0 nhưng không xóa dòng, và không giới hạn theo tồn kho.
    const maxQty = 999999;
    setState(() {
      final idx = _cart.indexWhere((i) => i.productId == item.productId);
      if (idx >= 0) {
        final clamped = newQty.clamp(0, maxQty);
        _cart[idx] = item.copyWith(quantity: clamped);
      }
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

  void _setQuickTender(double amount) {
    _tenderController.text = formatVndPrice(amount);
    setState(() {});
  }

  Future<void> _checkout() async {
    final payable = _cart.where((i) => i.quantity > 0).toList();
    if (payable.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa có hàng trong hóa đơn')),
      );
      return;
    }

    final tab = _tabs[_activeTabIndex];
    final items = List<SaleItem>.from(payable);
    final subtotal = items.fold(0.0, (s, i) => s + i.total);
    final total = (subtotal - tab.discountAmount).clamp(0.0, double.infinity).toDouble();

    final invoice = Invoice(
      id: const Uuid().v4(),
      items: items,
      subtotal: subtotal,
      discountAmount: tab.discountAmount,
      total: total,
      createdAt: DateTime.now(),
    );

    for (final item in items) {
      await StorageService.updateProductStock(item.productId, item.quantity);
    }
    await StorageService.saveInvoice(invoice);

    setState(() {
      tab.cart.clear();
      tab.discountAmount = 0;
      tab.tenderController.clear();
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
    final tab = _tabs[_activeTabIndex];
    final controller = TextEditingController(text: formatVndPrice(tab.discountAmount));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Giảm giá'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Số tiền giảm (VNĐ)',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            onPressed: () {
              final val = parseVndPrice(controller.text) ?? 0;
              setState(() => tab.discountAmount = val.clamp(0, _subtotal));
              Navigator.pop(ctx);
            },
            child: const Text('Áp dụng'),
          ),
        ],
      ),
    );
  }

  void _showEditPriceDialog(SaleItem item) {
    final controller = TextEditingController(text: formatVndPrice(item.price));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sửa đơn giá'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Đơn giá (VNĐ)',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            onPressed: () {
              final val = parseVndPrice(controller.text);
              if (val != null && val >= 0) {
                _updateCartItemPrice(item, val);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        titleSpacing: 0,
        title: LayoutBuilder(
          builder: (context, constraints) {
            final screenW = MediaQuery.sizeOf(context).width;
            final searchW = (screenW * 0.3).clamp(screenW * 0.2, screenW * 0.4).toDouble();
            return Row(
              children: [
                SizedBox(
                  width: searchW,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Tìm hoặc quét mã SP...',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.8)),
                      prefixIcon: const Icon(Icons.search, color: Colors.white),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.2),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    style: const TextStyle(color: Colors.white),
                    onTap: () {
                      if (!_showSearchResults) setState(() => _showSearchResults = true);
                    },
                    onChanged: (_) {
                      if (!_showSearchResults) setState(() => _showSearchResults = true);
                    },
                    onSubmitted: (_) => _addBySearch(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _tabScrollController,
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ...List.generate(
                            _tabs.length,
                            (i) => Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: _InvoiceTabChip(
                                    label: 'Hóa đơn ${i + 1}',
                                    isActive: i == _activeTabIndex,
                                    onTap: () => _switchTab(i),
                                    onClose: _tabs.length > 1 ? () => _closeTab(i) : null,
                                  ),
                                )),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: Colors.white),
                  onPressed: _addNewTab,
                  tooltip: 'Thêm hóa đơn mới',
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            );
          },
        ),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Container(
                        key: _cartScrollKey,
                        margin: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2)),
                          ],
                        ),
                        child: _cart.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
                                    const SizedBox(height: 12),
                                    Text('Chưa có hàng trong hóa đơn', style: TextStyle(color: Colors.grey[600])),
                                    const SizedBox(height: 8),
                                    Text('Tìm và thêm sản phẩm ở ô tìm kiếm trên', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                                  ],
                                ),
                              )
                            : LayoutBuilder(
                                builder: (context, constraints) {
                                  // Tăng minWidth để đủ chỗ cho cột SL rộng hơn, tránh overflow.
                                  final tableWidth = constraints.maxWidth < 860 ? 860.0 : constraints.maxWidth;
                                  return SingleChildScrollView(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: SizedBox(
                                        width: tableWidth,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            _buildCartHeader(),
                                            ...List.generate(_cart.length, (i) => _buildCartRow(_cart[i], i + 1)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
                if (_showSearchResults && _searchController.text.isNotEmpty && _filteredProducts.isNotEmpty) ...[
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _hideSearchResults,
                      child: const SizedBox.shrink(),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    top: 8,
                    child: Material(
                      elevation: 6,
                      borderRadius: BorderRadius.circular(10),
                      clipBehavior: Clip.antiAlias,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 280),
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: _filteredProducts.length,
                          separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[200]),
                          itemBuilder: (_, i) {
                            final p = _filteredProducts[i];
                            return _ProductSearchTile(
                              product: p,
                              onTap: () => _selectProductFromSearch(p),
                              formatCompact: _formatCompact,
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(width: 1, color: Colors.grey[300]),
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.white,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: TextField(
                        controller: _customerSearchController,
                        decoration: InputDecoration(
                          hintText: 'Tìm khách hàng...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.add, size: 20),
                            onPressed: () {},
                          ),
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSummaryRow('Tổng tiền hàng', '$_payableLinesCount sp', _formatCompact.format(_subtotal)),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: _subtotal > 0 ? _showDiscountDialog : null,
                            child: _buildSummaryRow('Giảm giá', '', '- ${_formatCompact.format(_discountAmount)}', highlight: _discountAmount > 0),
                          ),
                          const Divider(height: 24),
                          _buildSummaryRow('Khách cần trả', '', _formatCompact.format(_amountDue), bold: true, color: const Color(0xFF1565C0)),
                          const SizedBox(height: 12),
                          Text('Khách thanh toán', style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                          const SizedBox(height: 4),
                          TextField(
                            controller: _tenderController,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              hintText: _formatCompact.format(_amountDue),
                              border: const OutlineInputBorder(),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            runSpacing: 8,
                            spacing: 8,
                            children: [
                              _amountDue,
                              _amountDue + 1000,
                              _amountDue + 5000,
                              150000.0,
                              200000.0,
                              500000.0,
                            ].map((v) => _QuickTenderBtn(amount: v, onTap: () => _setQuickTender(v))).toList(),
                          ),
                          const SizedBox(height: 16),
                          Text('Phương thức', style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              _PaymentChip(
                                  label: 'Tiền mặt',
                                  value: 'cash',
                                  groupValue: _paymentMethod,
                                  onSelected: (v) => setState(() => _paymentMethod = v!)),
                              _PaymentChip(
                                  label: 'Chuyển khoản',
                                  value: 'transfer',
                                  groupValue: _paymentMethod,
                                  onSelected: (v) => setState(() => _paymentMethod = v!)),
                              _PaymentChip(
                                  label: 'Thẻ', value: 'card', groupValue: _paymentMethod, onSelected: (v) => setState(() => _paymentMethod = v!)),
                              _PaymentChip(
                                  label: 'Ví', value: 'wallet', groupValue: _paymentMethod, onSelected: (v) => setState(() => _paymentMethod = v!)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          OutlinedButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.print),
                            label: const Text('IN'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 48),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _hasPayableItems ? _checkout : null,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF1565C0),
                              minimumSize: const Size(double.infinity, 52),
                            ),
                            child: const Text('THANH TOÁN'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartHeader() {
    final screenW = MediaQuery.sizeOf(context).width;
    final isCompact = screenW < 1200;
    final headerFont = isCompact ? 11.0 : 12.0;
    final nameFlex = isCompact ? 3 : 4;
    final qtyFlex = isCompact ? 3 : 2;
    final actionWidth = isCompact ? 32.0 : 40.0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          SizedBox(width: 32, child: Text('#', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[700], fontSize: headerFont))),
          const SizedBox(width: 8),
          Expanded(
              flex: 2,
              child: Text('Mã SP',
                  style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[700], fontSize: headerFont), overflow: TextOverflow.ellipsis)),
          Expanded(
              flex: nameFlex,
              child: Text('Tên hàng',
                  style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[700], fontSize: headerFont), overflow: TextOverflow.ellipsis)),
          Expanded(
              flex: 1,
              child: Text('ĐVT',
                  style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[700], fontSize: headerFont), overflow: TextOverflow.ellipsis)),
          Expanded(flex: qtyFlex, child: Text('SL', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[700], fontSize: headerFont))),
          Expanded(
              flex: 1,
              child: Text('Đơn giá',
                  style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[700], fontSize: headerFont), overflow: TextOverflow.ellipsis)),
          Expanded(
              flex: 1,
              child: Text('Thành tiền',
                  style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[700], fontSize: headerFont), overflow: TextOverflow.ellipsis)),
          SizedBox(width: actionWidth),
        ],
      ),
    );
  }

  Widget _buildCartRow(SaleItem item, int index) {
    final screenW = MediaQuery.sizeOf(context).width;
    final isCompact = screenW < 1200;
    final nameFlex = isCompact ? 2 : 3;
    final qtyFlex = isCompact ? 3 : 2;
    final hideImage = screenW < 1050;

    final product = StorageService.getProductById(item.productId);
    final hasImage = product != null &&
        product.imagePath != null &&
        product.imagePath!.isNotEmpty &&
        (product.imagePath!.startsWith('http://') || product.imagePath!.startsWith('https://'));

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        child: Row(
          children: [
            SizedBox(width: 32, child: Text('$index', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
              onPressed: () => _removeFromCart(item),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            if (!hideImage && hasImage) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Image.network(
                    product.imagePath!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Container(color: Colors.grey[200], child: Icon(Icons.inventory_2_outlined, size: 20, color: Colors.grey[500])),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              flex: 2,
              child: Text(item.productCode, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
            ),
            Expanded(
              flex: nameFlex,
              child: Text(item.productName, style: const TextStyle(fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            Expanded(
              flex: 1,
              child: Text(item.unit, style: TextStyle(fontSize: 12, color: Colors.grey[600]), overflow: TextOverflow.ellipsis),
            ),
            Expanded(
              flex: qtyFlex,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove, size: 18),
                    onPressed: () => _updateCartItem(item, item.quantity - 1),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
                  Text('${item.quantity}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  IconButton(
                    icon: const Icon(Icons.add, size: 18),
                    onPressed: () => _updateCartItem(item, item.quantity + 1),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 1,
              child: InkWell(
                onTap: () => _showEditPriceDialog(item),
                child: Text(_formatCompact.format(item.price),
                    style: const TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
              ),
            ),
            Expanded(
              flex: 1,
              child: Text(_formatCompact.format(item.total),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline, size: 22, color: Color(0xFF1565C0)),
              onPressed: () => _updateCartItem(item, item.quantity + 1),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20),
              padding: EdgeInsets.zero,
              onSelected: (v) {
                if (v == 'edit_price') _showEditPriceDialog(item);
                if (v == 'remove') _removeFromCart(item);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit_price', child: Text('Sửa giá')),
                const PopupMenuItem(value: 'remove', child: Text('Xóa')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String extra, String value, {bool bold = false, Color? color, bool highlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : null, color: highlight ? Colors.orange : null)),
        Row(
          children: [
            if (extra.isNotEmpty) Text('$extra  ', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            Text(value, style: TextStyle(fontWeight: bold ? FontWeight.bold : null, fontSize: bold ? 18 : 14, color: color)),
          ],
        ),
      ],
    );
  }
}

class _ProductSearchTile extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  final NumberFormat formatCompact;

  const _ProductSearchTile({
    required this.product,
    required this.onTap,
    required this.formatCompact,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = product.imagePath != null &&
        product.imagePath!.isNotEmpty &&
        (product.imagePath!.startsWith('http://') || product.imagePath!.startsWith('https://'));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 56,
                  height: 56,
                    child: hasImage
                        ? Image.network(
                            product.imagePath!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _buildImagePlaceholder(),
                          )
                        : _buildImagePlaceholder(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        product.name,
                        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${formatCompact.format(product.price)} • ${product.code}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tồn: ${product.stock}',
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Icon(Icons.add_circle_outline, color: Colors.grey[400], size: 22),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    return Container(
      color: Colors.grey[300],
      child: Icon(Icons.inventory_2_outlined, color: Colors.grey[500], size: 28),
    );
  }
}

class _QuickTenderBtn extends StatelessWidget {
  final double amount;
  final VoidCallback onTap;

  const _QuickTenderBtn({required this.amount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,###', 'vi_VN');
    return Material(
      color: Colors.grey[200],
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(fmt.format(amount.toInt()), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ),
      ),
    );
  }
}

class _InvoiceTabChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onClose;

  const _InvoiceTabChip({
    required this.label,
    required this.isActive,
    required this.onTap,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isActive ? Colors.white : Colors.white.withOpacity(0.2),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isActive ? const Color(0xFF1565C0) : Colors.white,
                  fontWeight: isActive ? FontWeight.w600 : null,
                ),
              ),
              if (onClose != null) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: onClose,
                  child: Icon(
                    Icons.close,
                    size: 16,
                    color: isActive ? Colors.grey[700] : Colors.white70,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentChip extends StatelessWidget {
  final String label;
  final String value;
  final String groupValue;
  final void Function(String?) onSelected;

  const _PaymentChip({required this.label, required this.value, required this.groupValue, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(value),
    );
  }
}
