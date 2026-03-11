import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/product.dart';
import '../models/sale_item.dart';
import '../models/invoice.dart';
import '../services/storage_service.dart';
import '../services/print_service.dart';
import '../utils/price_validator.dart';
import '../utils/vnd_input_formatter.dart';

class SalesScreen extends StatefulWidget {
  final bool isActive;

  const SalesScreen({super.key, this.isActive = true});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _InvoiceTabData {
  final String id;
  List<SaleItem> cart;
  double discountValue;
  String discountType; // amount | percent
  final TextEditingController customerController;
  final TextEditingController tenderController;
  String paymentMethod;

  _InvoiceTabData({
    required this.id,
    List<SaleItem>? cart,
  })  : cart = cart ?? [],
        discountValue = 0,
        discountType = 'amount',
        customerController = TextEditingController(),
        tenderController = TextEditingController(),
        paymentMethod = 'bank';
}

class _BankQrProfile {
  final String id;
  final String name;
  final String qrTemplate;
  final String? bankCode;
  final String? bankName;
  final String? accountNumber;
  final String? accountName;

  const _BankQrProfile({
    required this.id,
    required this.name,
    required this.qrTemplate,
    this.bankCode,
    this.bankName,
    this.accountNumber,
    this.accountName,
  });

  factory _BankQrProfile.fromMap(Map<String, dynamic> map) {
    return _BankQrProfile(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      qrTemplate: (map['qrTemplate'] ?? '').toString(),
      bankCode: map['bankCode']?.toString(),
      bankName: map['bankName']?.toString(),
      accountNumber: map['accountNumber']?.toString(),
      accountName: map['accountName']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'qrTemplate': qrTemplate,
      'bankCode': bankCode,
      'bankName': bankName,
      'accountNumber': accountNumber,
      'accountName': accountName,
    };
  }
}

class _VietnamBank {
  final String code;
  final String name;

  const _VietnamBank({required this.code, required this.name});
}

class _SalesScreenState extends State<SalesScreen> {
  static const List<_VietnamBank> _vietnamBanks = [
    _VietnamBank(code: 'vietcombank', name: 'Vietcombank'),
    _VietnamBank(code: 'vietinbank', name: 'VietinBank'),
    _VietnamBank(code: 'bidv', name: 'BIDV'),
    _VietnamBank(code: 'agribank', name: 'Agribank'),
    _VietnamBank(code: 'mbbank', name: 'MB Bank'),
    _VietnamBank(code: 'acb', name: 'ACB'),
    _VietnamBank(code: 'techcombank', name: 'Techcombank'),
    _VietnamBank(code: 'vpbank', name: 'VPBank'),
    _VietnamBank(code: 'tpbank', name: 'TPBank'),
    _VietnamBank(code: 'sacombank', name: 'Sacombank'),
    _VietnamBank(code: 'hdbank', name: 'HDBank'),
    _VietnamBank(code: 'ocb', name: 'OCB'),
    _VietnamBank(code: 'seabank', name: 'SeABank'),
    _VietnamBank(code: 'vib', name: 'VIB'),
    _VietnamBank(code: 'shb', name: 'SHB'),
    _VietnamBank(code: 'msb', name: 'MSB'),
    _VietnamBank(code: 'eximbank', name: 'Eximbank'),
  ];

  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _searchKeyListenerFocusNode = FocusNode(skipTraversal: true);
  final _tabScrollController = ScrollController();
  final _searchDropdownScrollController = ScrollController();
  final _cartScrollKey = GlobalKey();
  bool _showSearchResults = true;
  int _searchFocusIndex = -1;
  final List<_InvoiceTabData> _tabs = [];
  int _activeTabIndex = 0;
  int _tabCounter = 1;
  List<Product> _products = [];
  List<Product> _filteredProducts = [];
  final _formatCurrency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫');
  final _formatCompact = NumberFormat('#,###', 'vi_VN');
  bool _isAddingBySearch = false;
  DateTime? _lastAddBySearchAt;
  bool _ignoreNextSubmitted = false;
  String? _lastAutoAddedCode;
  DateTime? _lastAutoAddedAt;
  String _lastProcessedSearchText = '';
  List<_BankQrProfile> _bankQrProfiles = [];
  String? _defaultBankQrId;
  String? _selectedBankQrId;

  List<SaleItem> get _cart => _tabs.isNotEmpty ? _tabs[_activeTabIndex].cart : [];
  TextEditingController get _customerController => _tabs.isNotEmpty ? _tabs[_activeTabIndex].customerController : TextEditingController();
  double get _discountAmount => _tabs.isNotEmpty ? _calculateDiscountAmount(_tabs[_activeTabIndex], _subtotal) : 0;
  String get _discountType => _tabs.isNotEmpty ? _tabs[_activeTabIndex].discountType : 'amount';
  double get _discountValue => _tabs.isNotEmpty ? _tabs[_activeTabIndex].discountValue : 0;
  String get _discountDisplayText {
    final amountText = _formatCompact.format(_discountAmount);
    if (_discountType == 'percent') {
      return '- ${_discountValue.toStringAsFixed(_discountValue % 1 == 0 ? 0 : 1)}% ($amountText)';
    }
    return '- $amountText';
  }

  TextEditingController get _tenderController => _tabs.isNotEmpty ? _tabs[_activeTabIndex].tenderController : TextEditingController();
  String get _paymentMethod => _tabs.isNotEmpty ? _tabs[_activeTabIndex].paymentMethod : 'bank';
  set _paymentMethod(String v) {
    if (_tabs.isNotEmpty) _tabs[_activeTabIndex].paymentMethod = v;
  }

  _BankQrProfile? get _activeBankQrProfile {
    final selected = _bankQrProfiles.where((e) => e.id == _selectedBankQrId).firstOrNull;
    if (selected != null) return selected;
    return _bankQrProfiles.where((e) => e.id == _defaultBankQrId).firstOrNull;
  }

  _VietnamBank? _findBankByCode(String? code) {
    if (code == null || code.trim().isEmpty) return null;
    return _vietnamBanks.where((e) => e.code == code).firstOrNull;
  }

  @override
  void initState() {
    super.initState();
    _tabs.add(_InvoiceTabData(id: 'tab_1', cart: []));
    _loadProducts();
    _loadBankQrProfiles();
    _searchController.addListener(_filterProducts);
  }

  @override
  void didUpdateWidget(covariant SalesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _loadProducts();
      _loadBankQrProfiles();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchKeyListenerFocusNode.dispose();
    _tabScrollController.dispose();
    _searchDropdownScrollController.dispose();
    for (final t in _tabs) {
      t.customerController.dispose();
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
    final tab = _tabs[index];
    final hasItems = tab.cart.isNotEmpty;
    final isSingleTab = _tabs.length <= 1;
    final closed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(isSingleTab ? 'Xóa giỏ hàng' : 'Đóng hóa đơn'),
        content: Text(
          hasItems
              ? (isSingleTab
                  ? 'Giỏ hàng hiện có ${tab.cart.length} mặt hàng. Bạn có chắc muốn xóa toàn bộ?'
                  : 'Hóa đơn ${index + 1} còn ${tab.cart.length} mặt hàng chưa thanh toán. Đóng hóa đơn sẽ xóa toàn bộ. Bạn có chắc?')
              : (isSingleTab ? 'Giỏ hàng đang trống. Bạn có muốn làm mới hóa đơn này?' : 'Bạn có chắc muốn đóng Hóa đơn ${index + 1}?'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(isSingleTab ? 'Xóa hết' : 'Đóng'),
          ),
        ],
      ),
    );
    if (closed != true || !mounted) return;
    setState(() {
      if (isSingleTab) {
        tab.cart.clear();
        tab.discountType = 'amount';
        tab.discountValue = 0;
        tab.customerController.clear();
        tab.tenderController.clear();
        tab.paymentMethod = 'bank';
      } else {
        tab.customerController.dispose();
        tab.tenderController.dispose();
        _tabs.removeAt(index);
        if (_activeTabIndex >= _tabs.length) _activeTabIndex = _tabs.length - 1;
        if (_activeTabIndex > index) _activeTabIndex--;
      }
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

  void _loadBankQrProfiles() {
    final maps = StorageService.getBankQrProfiles();
    final profiles = maps.map(_BankQrProfile.fromMap).where((e) => e.id.trim().isNotEmpty && e.name.trim().isNotEmpty).toList();
    final defaultId = StorageService.getDefaultBankQrId();
    String? selectedId = _selectedBankQrId;
    if (selectedId != null && profiles.every((e) => e.id != selectedId)) {
      selectedId = null;
    }
    if (selectedId == null && defaultId != null && profiles.any((e) => e.id == defaultId)) {
      selectedId = defaultId;
    }
    setState(() {
      _bankQrProfiles = profiles;
      _defaultBankQrId = defaultId;
      _selectedBankQrId = selectedId;
    });
  }

  String _buildPaymentQrData(String qrTemplate, double amount) {
    final amountValue = amount.round().clamp(0, 999999999);
    return qrTemplate.replaceAll('{amount}', amountValue.toString());
  }

  String? _buildVietQrImageUrl(_BankQrProfile profile, double amount) {
    final bankCode = profile.bankCode?.trim() ?? '';
    final accountNumber = profile.accountNumber?.trim() ?? '';
    if (bankCode.isEmpty || accountNumber.isEmpty) return null;
    final amountValue = amount.round().clamp(0, 999999999);
    final addInfo = Uri.encodeComponent('Thanh toan hoa don');
    final accountName = Uri.encodeComponent((profile.accountName ?? '').trim());
    final accountPart = accountName.isEmpty ? '' : '&accountName=$accountName';
    return 'https://img.vietqr.io/image/$bankCode-$accountNumber-compact2.png?amount=$amountValue&addInfo=$addInfo$accountPart';
  }

  Future<void> _saveBankQrProfiles() async {
    await StorageService.saveBankQrProfiles(_bankQrProfiles.map((e) => e.toMap()).toList());
    await StorageService.setDefaultBankQrId(_defaultBankQrId);
  }

  Future<void> _showBankQrDialog({_BankQrProfile? editing}) async {
    final accountController = TextEditingController(text: editing?.accountNumber ?? '');
    String? selectedBankCode = editing?.bankCode;
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: Text(editing == null ? 'Thêm tài khoản ngân hàng' : 'Sửa tài khoản ngân hàng'),
          content: SizedBox(
            width: 420,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedBankCode,
                    decoration: const InputDecoration(
                      labelText: 'Ngân hàng',
                      border: OutlineInputBorder(),
                    ),
                    items: _vietnamBanks
                        .map(
                          (e) => DropdownMenuItem<String>(
                            value: e.code,
                            child: Text(e.name, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setStateDialog(() => selectedBankCode = value),
                    validator: (v) => (v == null || v.isEmpty) ? 'Chọn ngân hàng' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: accountController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Số tài khoản',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập số tài khoản' : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                Navigator.of(ctx).pop(true);
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;

    final bank = _findBankByCode(selectedBankCode);
    final bankCode = selectedBankCode?.trim() ?? '';
    final bankName = bank?.name ?? '';
    final accountNumber = accountController.text.trim();
    final name = '$bankName - $accountNumber';
    final qrTemplate = editing?.qrTemplate ?? '';
    setState(() {
      if (editing == null) {
        final profile = _BankQrProfile(
          id: const Uuid().v4(),
          name: name,
          qrTemplate: qrTemplate,
          bankCode: bankCode,
          bankName: bankName,
          accountNumber: accountNumber,
          accountName: editing?.accountName,
        );
        _bankQrProfiles.add(profile);
        _selectedBankQrId = profile.id;
        _defaultBankQrId ??= profile.id;
      } else {
        final idx = _bankQrProfiles.indexWhere((e) => e.id == editing.id);
        if (idx >= 0) {
          _bankQrProfiles[idx] = _BankQrProfile(
            id: editing.id,
            name: name,
            qrTemplate: qrTemplate,
            bankCode: bankCode,
            bankName: bankName,
            accountNumber: accountNumber,
            accountName: editing.accountName,
          );
          _selectedBankQrId = editing.id;
        }
      }
    });
    await _saveBankQrProfiles();
  }

  Future<void> _deleteSelectedBankQr() async {
    final selected = _activeBankQrProfile;
    if (selected == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa mã QR'),
        content: Text('Bạn có chắc muốn xóa "${selected.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _bankQrProfiles.removeWhere((e) => e.id == selected.id);
      if (_defaultBankQrId == selected.id) {
        _defaultBankQrId = _bankQrProfiles.isNotEmpty ? _bankQrProfiles.first.id : null;
      }
      _selectedBankQrId =
          _bankQrProfiles.any((e) => e.id == _selectedBankQrId) ? _selectedBankQrId : (_bankQrProfiles.isNotEmpty ? _bankQrProfiles.first.id : null);
    });
    await _saveBankQrProfiles();
  }

  void _filterProducts() {
    final query = _searchController.text.trim();
    final queryLower = query.toLowerCase();
    final textChanged = query != _lastProcessedSearchText;
    _lastProcessedSearchText = query;

    if (query.isEmpty) {
      setState(() => _filteredProducts = List.from(_products));
      return;
    }

    // Khớp chính xác mã vạch/mã SP thì thêm ngay vào giỏ hàng.
    final exactMatch = _products.where((p) => p.code.toLowerCase() == queryLower).toList();
    if (exactMatch.length == 1 && textChanged) {
      Future.microtask(() {
        if (!mounted) return;
        _upsertCartItem(exactMatch.first, qty: 1);
        _ignoreNextSubmitted = true;
        _lastAutoAddedCode = queryLower;
        _lastAutoAddedAt = DateTime.now();
        setState(() {
          _filteredProducts = List.from(_products);
          _showSearchResults = false;
          _searchFocusIndex = -1;
        });
        _focusSearchForNextScan();
      });
      return;
    }

    setState(() {
      _filteredProducts = _products.where((p) => p.name.toLowerCase().contains(queryLower) || p.code.toLowerCase().contains(queryLower)).toList();
      _searchFocusIndex = -1;
    });
  }

  double get _subtotal => _cart.fold(0, (sum, item) => sum + item.total);
  double get _amountDue => (_subtotal - _discountAmount).clamp(0, double.infinity);
  bool get _hasPayableItems => _cart.any((i) => i.quantity > 0);
  int get _payableLinesCount => _cart.where((i) => i.quantity > 0).length;

  double _calculateDiscountAmount(_InvoiceTabData tab, double subtotal) {
    if (subtotal <= 0) return 0;
    if (tab.discountType == 'percent') {
      final pct = tab.discountValue.clamp(0, 100);
      return (subtotal * pct / 100).clamp(0, subtotal).toDouble();
    }
    return tab.discountValue.clamp(0, subtotal).toDouble();
  }

  void _upsertCartItem(Product product, {int qty = 1}) {
    // Không phụ thuộc tồn kho: cho phép tăng số lượng tự do.
    const maxQty = 999999;
    final existing = _cart.where((i) => i.productId == product.id).firstOrNull;
    if (existing != null) {
      final requested = existing.quantity + qty;
      final newQty = requested.clamp(0, maxQty);
      final updated = existing.copyWith(quantity: newQty);
      _cart.removeWhere((i) => i.productId == product.id);
      _cart.insert(0, updated);
    } else {
      _cart.insert(
          0,
          SaleItem(
            productId: product.id,
            productName: product.name,
            productCode: product.code,
            unit: product.unit,
            price: product.price,
            quantity: qty.clamp(0, maxQty),
          ));
    }
  }

  void _handleSearchKey(KeyEvent event) {
    if (!_showSearchResults || _filteredProducts.isEmpty) return;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _searchFocusIndex = (_searchFocusIndex + 1).clamp(0, _filteredProducts.length - 1);
        _scrollDropdownToIndex(_searchFocusIndex);
      });
    } else if (key == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _searchFocusIndex = (_searchFocusIndex - 1).clamp(0, _filteredProducts.length - 1);
        _scrollDropdownToIndex(_searchFocusIndex);
      });
    } else if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      if (_searchFocusIndex >= 0 && _searchFocusIndex < _filteredProducts.length) {
        _selectProductFromSearch(_filteredProducts[_searchFocusIndex]);
      } else {
        _addBySearch();
      }
    } else if (key == LogicalKeyboardKey.escape) {
      _hideSearchResults();
    }
  }

  void _scrollDropdownToIndex(int index) {
    const itemHeight = 76.0;
    final offset = (index * itemHeight).clamp(
      0.0,
      _searchDropdownScrollController.hasClients ? _searchDropdownScrollController.position.maxScrollExtent : double.infinity,
    );
    if (_searchDropdownScrollController.hasClients) {
      _searchDropdownScrollController.animateTo(
        offset,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
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

  void _focusSearchForNextScan() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_searchFocusNode.hasFocus) _searchFocusNode.requestFocus();
      if (_searchController.text.isNotEmpty) {
        _searchController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _searchController.text.length,
        );
      }
      // Một số máy quét gửi Enter + ký tự kết thúc làm TextField mất focus muộn.
      // Re-focus thêm 1 nhịp ngắn để giữ ô quét luôn sẵn sàng.
      Future.delayed(const Duration(milliseconds: 80), () {
        if (!mounted) return;
        if (!_searchFocusNode.hasFocus) _searchFocusNode.requestFocus();
        if (_searchController.text.isNotEmpty) {
          _searchController.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _searchController.text.length,
          );
        }
      });
    });
  }

  void _selectProductFromSearch(Product chosen) {
    Future.microtask(() {
      if (!mounted) return;
      setState(() {
        _upsertCartItem(chosen, qty: 1);
        _searchController.text = chosen.code;
        _showSearchResults = false;
        _searchFocusIndex = -1;
      });
      _focusSearchForNextScan();
    });
  }

  Future<void> _selectFirstResultOnEnter() async {
    final q = _searchController.text.trim();
    if (q.isEmpty) return;

    final exact = _products.where((p) => p.code.toLowerCase() == q.toLowerCase()).firstOrNull;
    if (exact != null) {
      setState(() {
        _upsertCartItem(exact, qty: 1);
        _showSearchResults = false;
        _searchFocusIndex = -1;
      });
      _focusSearchForNextScan();
      return;
    }

    final chosen = exact ?? (_filteredProducts.isNotEmpty ? _filteredProducts.first : null);
    if (chosen != null) {
      _selectProductFromSearch(chosen);
      return;
    }

    final created = await _showQuickAddProductDialog(q);
    if (created == null || !mounted) {
      _focusSearchForNextScan();
      return;
    }

    _loadProducts();
    setState(() {
      _upsertCartItem(created, qty: 1);
      _searchFocusIndex = -1;
      _showSearchResults = false;
      _searchController.text = created.code;
    });
    _focusSearchForNextScan();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã thêm "${created.name}" và đưa vào giỏ hàng'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _addBySearch() async {
    final queryLower = _searchController.text.trim().toLowerCase();
    if (_ignoreNextSubmitted &&
        _lastAutoAddedCode == queryLower &&
        _lastAutoAddedAt != null &&
        DateTime.now().difference(_lastAutoAddedAt!).inMilliseconds < 600) {
      _ignoreNextSubmitted = false;
      _focusSearchForNextScan();
      return;
    }
    _ignoreNextSubmitted = false;

    final now = DateTime.now();
    if (_lastAddBySearchAt != null && now.difference(_lastAddBySearchAt!).inMilliseconds < 80) {
      _focusSearchForNextScan();
      return;
    }
    if (_isAddingBySearch) {
      _focusSearchForNextScan();
      return;
    }
    _isAddingBySearch = true;
    _lastAddBySearchAt = now;
    try {
      await _selectFirstResultOnEnter();
    } finally {
      _isAddingBySearch = false;
      _focusSearchForNextScan();
    }
  }

  Future<Product?> _showQuickAddProductDialog(String barcode) async {
    final normalizedCode = barcode.trim();
    if (normalizedCode.isEmpty) return null;

    final existed = _products.where((p) => p.code.toLowerCase() == normalizedCode.toLowerCase()).firstOrNull;
    if (existed != null) return existed;

    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    final stockController = TextEditingController(text: '0');
    final unitController = TextEditingController(text: 'cái');

    final result = await showDialog<Product>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Mã chưa có - thêm sản phẩm'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  initialValue: normalizedCode,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Mã vạch / Mã SP',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.qr_code),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Tên sản phẩm',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.shopping_bag),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập tên sản phẩm' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: priceController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, VndPriceInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Giá bán (VNĐ)',
                    hintText: 'VD: 15.000',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.sell),
                  ),
                  validator: (v) => validateVndPrice(v, fieldName: 'Giá bán'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: stockController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(
                          labelText: 'Tồn kho',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.inventory_2),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Nhập tồn kho';
                          final parsed = int.tryParse(v);
                          if (parsed == null) return 'Tồn kho không hợp lệ';
                          if (parsed < 0) return 'Tồn kho phải >= 0';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: unitController,
                        decoration: const InputDecoration(
                          labelText: 'Đơn vị',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.straighten),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Hủy'),
          ),
          FilledButton.icon(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;

              final duplicate = StorageService.getProducts().where((p) => p.code.toLowerCase() == normalizedCode.toLowerCase()).firstOrNull;
              if (duplicate != null) {
                if (!ctx.mounted) return;
                Navigator.of(ctx).pop(duplicate);
                return;
              }

              final newProduct = Product(
                id: const Uuid().v4(),
                name: nameController.text.trim(),
                code: normalizedCode,
                price: parseVndPrice(priceController.text) ?? 0,
                stock: int.tryParse(stockController.text) ?? 0,
                unit: unitController.text.trim().isEmpty ? 'cái' : unitController.text.trim(),
              );
              await StorageService.addProduct(newProduct);
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop(newProduct);
            },
            icon: const Icon(Icons.save),
            label: const Text('Thêm và bán'),
          ),
        ],
      ),
    );

    nameController.dispose();
    priceController.dispose();
    stockController.dispose();
    unitController.dispose();
    return result;
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
    final discount = _calculateDiscountAmount(tab, subtotal);
    final total = (subtotal - discount).clamp(0.0, double.infinity).toDouble();
    final customerName = tab.customerController.text.trim();

    final invoice = Invoice(
      id: const Uuid().v4(),
      items: items,
      subtotal: subtotal,
      discountAmount: discount,
      discountType: tab.discountType,
      discountValue: tab.discountValue,
      total: total,
      createdAt: DateTime.now(),
      customerName: customerName.isEmpty ? null : customerName,
    );

    for (final item in items) {
      await StorageService.updateProductStock(item.productId, item.quantity);
    }
    await StorageService.saveInvoice(invoice);

    setState(() {
      tab.cart.clear();
      tab.discountType = 'amount';
      tab.discountValue = 0;
      tab.customerController.clear();
      tab.tenderController.clear();
    });

    if (!mounted) return;

    // Hỏi có muốn in hoá đơn không
    final shouldPrint = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Thanh toán thành công'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tổng: ${_formatCurrency.format(invoice.total)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text('Bạn có muốn in hoá đơn không?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Không in'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.print),
            label: const Text('In hoá đơn'),
          ),
        ],
      ),
    );

    if (shouldPrint == true && mounted) {
      final qrProfile = _activeBankQrProfile;
      await PrintService.printInvoice(
        context: context,
        items: items,
        subtotal: subtotal,
        discountAmount: discount,
        total: total,
        invoiceId: invoice.id,
        createdAt: invoice.createdAt,
        customerName: invoice.customerName,
        paymentQrData: qrProfile == null ? null : (qrProfile.qrTemplate.trim().isEmpty ? null : _buildPaymentQrData(qrProfile.qrTemplate, total)),
        paymentQrLabel: qrProfile?.name,
        paymentQrImageUrl: qrProfile == null ? null : _buildVietQrImageUrl(qrProfile, total),
      );
    }
  }

  void _showDiscountDialog() {
    final tab = _tabs[_activeTabIndex];
    var selectedType = tab.discountType;
    final controller = TextEditingController(
      text: selectedType == 'percent'
          ? (tab.discountValue % 1 == 0 ? tab.discountValue.toInt().toString() : tab.discountValue.toString())
          : formatVndPrice(tab.discountValue),
    );
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('Giảm giá'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'amount', label: Text('Theo tiền')),
                    ButtonSegment(value: 'percent', label: Text('Theo %')),
                  ],
                  selected: {selectedType},
                  onSelectionChanged: (selection) {
                    selectedType = selection.first;
                    controller.text = selectedType == 'percent' ? '0' : '';
                    setStateDialog(() {});
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                  decoration: InputDecoration(
                    labelText: selectedType == 'percent' ? 'Phần trăm giảm (%)' : 'Số tiền giảm (VNĐ)',
                    border: const OutlineInputBorder(),
                    helperText: selectedType == 'percent' ? '0 - 100' : null,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            FilledButton(
              onPressed: () {
                if (selectedType == 'percent') {
                  final raw = double.tryParse(controller.text.trim().replaceAll(',', '.')) ?? 0;
                  setState(() {
                    tab.discountType = 'percent';
                    tab.discountValue = raw.clamp(0, 100).toDouble();
                  });
                } else {
                  final raw = parseVndPrice(controller.text) ?? 0;
                  setState(() {
                    tab.discountType = 'amount';
                    tab.discountValue = raw.clamp(0, _subtotal).toDouble();
                  });
                }
                Navigator.pop(ctx);
              },
              child: const Text('Áp dụng'),
            ),
          ],
        ),
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
                  child: KeyboardListener(
                    focusNode: _searchKeyListenerFocusNode,
                    onKeyEvent: _handleSearchKey,
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
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
                        if (_searchController.text.isNotEmpty) {
                          _searchController.selection = TextSelection(
                            baseOffset: 0,
                            extentOffset: _searchController.text.length,
                          );
                        }
                      },
                      onChanged: (_) {
                        if (!_showSearchResults) setState(() => _showSearchResults = true);
                      },
                      onSubmitted: (_) => _addBySearch(),
                      onEditingComplete: _focusSearchForNextScan,
                    ),
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
                                    onClose: () => _closeTab(i),
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
                          controller: _searchDropdownScrollController,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: _filteredProducts.length,
                          separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[200]),
                          itemBuilder: (_, i) {
                            final p = _filteredProducts[i];
                            return _ProductSearchTile(
                              product: p,
                              onTap: () => _selectProductFromSearch(p),
                              formatCompact: _formatCompact,
                              highlighted: i == _searchFocusIndex,
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
          SizedBox(
            width: 400,
            child: Container(
              color: Colors.white,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _customerController,
                            decoration: const InputDecoration(
                              labelText: 'Tên khách hàng',
                              hintText: 'Nhập tên khách (tuỳ chọn)',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildSummaryRow('Tổng tiền hàng', '$_payableLinesCount sp', _formatCompact.format(_subtotal)),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: _subtotal > 0 ? _showDiscountDialog : null,
                            child: _buildSummaryRow(
                              _discountType == 'percent' ? 'Giảm giá (%)' : 'Giảm giá',
                              '',
                              _discountDisplayText,
                              highlight: _discountAmount > 0,
                            ),
                          ),
                          const Divider(height: 24),
                          _buildSummaryRow('Khách cần trả', '', _formatCompact.format(_amountDue), bold: true, color: const Color(0xFF1565C0)),
                          const SizedBox(height: 12),
                          Text('Phương thức', style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _PaymentChip(
                                  label: 'Tiền mặt',
                                  value: 'cash',
                                  groupValue: _paymentMethod,
                                  onSelected: (v) => setState(() => _paymentMethod = v ?? 'cash'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _PaymentChip(
                                  label: 'Chuyển khoản',
                                  value: 'bank',
                                  groupValue: _paymentMethod,
                                  onSelected: (v) => setState(() => _paymentMethod = v ?? 'cash'),
                                ),
                              ),
                            ],
                          ),
                          if (_paymentMethod == 'bank') ...[
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              value: _activeBankQrProfile?.id,
                              decoration: const InputDecoration(
                                labelText: 'Mã QR ngân hàng',
                                border: OutlineInputBorder(),
                              ),
                              hint: const Text('Chọn mã QR để in theo hóa đơn'),
                              items: _bankQrProfiles
                                  .map(
                                    (e) => DropdownMenuItem<String>(
                                      value: e.id,
                                      child: Text(
                                        '${e.bankName ?? ''} - ${e.accountNumber ?? ''}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                setState(() => _selectedBankQrId = value);
                              },
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Khi in hóa đơn sẽ tự render QR ngân hàng kèm số tiền khách cần thanh toán.',
                              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _showBankQrDialog(),
                                    icon: const Icon(Icons.add, size: 16),
                                    label: const Text('Thêm'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _activeBankQrProfile == null ? null : () => _showBankQrDialog(editing: _activeBankQrProfile),
                                    icon: const Icon(Icons.edit, size: 16),
                                    label: const Text('Sửa'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _activeBankQrProfile == null ? null : _deleteSelectedBankQr,
                                    icon: const Icon(Icons.delete_outline, size: 16),
                                    label: const Text('Xóa'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          OutlinedButton.icon(
                            onPressed: _hasPayableItems
                                ? () async {
                                    final payable = _cart.where((i) => i.quantity > 0).toList();
                                    final subtotal = payable.fold(0.0, (s, i) => s + i.total);
                                    final tab = _tabs[_activeTabIndex];
                                    final discount = _calculateDiscountAmount(tab, subtotal);
                                    final total = (subtotal - discount).clamp(0.0, double.infinity).toDouble();
                                    final qrProfile = _activeBankQrProfile;
                                    await PrintService.printInvoice(
                                      context: context,
                                      items: payable,
                                      subtotal: subtotal,
                                      discountAmount: discount,
                                      total: total,
                                      customerName: tab.customerController.text.trim().isEmpty ? null : tab.customerController.text.trim(),
                                      paymentQrData: qrProfile == null
                                          ? null
                                          : (qrProfile.qrTemplate.trim().isEmpty ? null : _buildPaymentQrData(qrProfile.qrTemplate, total)),
                                      paymentQrLabel: qrProfile?.name,
                                      paymentQrImageUrl: qrProfile == null ? null : _buildVietQrImageUrl(qrProfile, total),
                                    );
                                  }
                                : null,
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

  // Layout cột cố định dùng chung cho header và row:
  // [32] # | [28] del | [Expanded(2)] mã | [Expanded(3)] tên | [56] ĐVT | [110] SL (−/+) | [80] đơn giá | [80] thành tiền | [32] menu
  static const double _colDel = 28;
  static const double _colDvt = 56;
  static const double _colQty = 110;
  static const double _colPrice = 80;
  static const double _colTotal = 88;
  static const double _colMenu = 32;
  static const double _colIdx = 32;
  static const double _colGap = 8;

  Widget _buildCartHeader() {
    final style = TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[700], fontSize: 12);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          SizedBox(width: _colIdx, child: Text('#', style: style)),
          SizedBox(width: _colGap + _colDel),
          Expanded(flex: 2, child: Text('Mã SP', style: style, overflow: TextOverflow.ellipsis)),
          Expanded(flex: 3, child: Text('Tên hàng', style: style, overflow: TextOverflow.ellipsis)),
          SizedBox(width: _colDvt, child: Text('ĐVT', style: style, overflow: TextOverflow.ellipsis)),
          SizedBox(width: _colQty, child: Center(child: Text('SL', style: style))),
          SizedBox(width: _colPrice, child: Text('Đơn giá', style: style, textAlign: TextAlign.right)),
          SizedBox(width: _colTotal, child: Text('Thành tiền', style: style, textAlign: TextAlign.right)),
          SizedBox(width: _colMenu),
        ],
      ),
    );
  }

  Widget _buildCartRow(SaleItem item, int index) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // #
            SizedBox(
              width: _colIdx,
              child: Text('$index', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            // Xóa
            const SizedBox(width: _colGap / 2),
            SizedBox(
              width: _colDel,
              child: IconButton(
                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                onPressed: () => _removeFromCart(item),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ),
            // Mã SP
            Expanded(
              flex: 2,
              child: SelectableText(
                item.productCode,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                maxLines: 1,
              ),
            ),
            // Tên hàng
            Expanded(
              flex: 3,
              child: SelectableText(
                item.productName,
                style: const TextStyle(fontSize: 13),
                maxLines: 2,
              ),
            ),
            // ĐVT
            SizedBox(
              width: _colDvt,
              child: Text(item.unit, style: TextStyle(fontSize: 12, color: Colors.grey[600]), overflow: TextOverflow.ellipsis),
            ),
            // SL: − số +
            SizedBox(
              width: _colQty,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove, size: 16),
                    onPressed: () => _updateCartItem(item, item.quantity - 1),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  ),
                  SizedBox(
                    width: 44,
                    child: _QtyInput(
                      value: item.quantity,
                      onSubmitted: (newQty) => _updateCartItem(item, newQty),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, size: 16),
                    onPressed: () => _updateCartItem(item, item.quantity + 1),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  ),
                ],
              ),
            ),
            // Đơn giá (bấm để sửa)
            SizedBox(
              width: _colPrice,
              child: InkWell(
                onTap: () => _showEditPriceDialog(item),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  child: Text(_formatCompact.format(item.price),
                      textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.w500)),
                ),
              ),
            ),
            // Thành tiền
            SizedBox(
              width: _colTotal,
              child: Text(_formatCompact.format(item.total),
                  textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            // Menu
            SizedBox(
              width: _colMenu,
              child: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 18),
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
            Text(value, style: TextStyle(fontWeight: bold ? FontWeight.bold : null, fontSize: bold ? 24 : 18, color: color)),
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
  final bool highlighted;

  const _ProductSearchTile({
    required this.product,
    required this.onTap,
    required this.formatCompact,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = product.imagePath != null &&
        product.imagePath!.isNotEmpty &&
        (product.imagePath!.startsWith('http://') || product.imagePath!.startsWith('https://'));

    return Material(
      color: highlighted ? const Color(0xFFE3F2FD) : Colors.transparent,
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
                    SelectableText(
                      '${formatCompact.format(product.price)} • ${product.code}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      maxLines: 1,
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

class _QtyInput extends StatefulWidget {
  final int value;
  final ValueChanged<int> onSubmitted;

  const _QtyInput({
    required this.value,
    required this.onSubmitted,
  });

  @override
  State<_QtyInput> createState() => _QtyInputState();
}

class _QtyInputState extends State<_QtyInput> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.value}');
  }

  @override
  void didUpdateWidget(covariant _QtyInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && oldWidget.value != widget.value) {
      _controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _applyValue(String raw) {
    final parsed = int.tryParse(raw.trim());
    if (parsed == null) {
      _controller.text = '${widget.value}';
      return;
    }
    final clamped = parsed.clamp(0, 999999);
    _controller.text = '$clamped';
    widget.onSubmitted(clamped);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      onTap: () => _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      ),
      onSubmitted: _applyValue,
      onTapOutside: (_) {
        _applyValue(_controller.text);
        _focusNode.unfocus();
      },
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
