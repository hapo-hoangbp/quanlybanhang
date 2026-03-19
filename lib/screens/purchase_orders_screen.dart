import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../models/product.dart';
import '../models/purchase_order.dart';
import '../services/purchase_export_service.dart';
import '../services/print_service.dart';
import '../services/storage_service.dart';
import '../utils/price_validator.dart';
import '../utils/vnd_input_formatter.dart';

class PurchaseOrdersScreen extends StatefulWidget {
  final bool isActive;

  const PurchaseOrdersScreen({super.key, this.isActive = true});

  @override
  State<PurchaseOrdersScreen> createState() => _PurchaseOrdersScreenState();
}

class _PurchaseOrdersScreenState extends State<PurchaseOrdersScreen> {
  final _formatNumber = NumberFormat('#,###', 'vi_VN');
  final _formatDate = DateFormat('dd/MM/yyyy HH:mm');
  final _formatDay = DateFormat('dd/MM/yyyy');
  final Set<String> _selectedIds = <String>{};
  final TextEditingController _searchController = TextEditingController();
  DateTimeRange? _selectedRange;

  List<PurchaseOrder> _orders = [];
  List<Product> _products = [];

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  @override
  void didUpdateWidget(covariant PurchaseOrdersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _loadOrders();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadOrders() {
    setState(() {
      _orders = StorageService.getPurchaseOrders();
      _products = StorageService.getProducts();
      _selectedIds.removeWhere((id) => !_orders.any((o) => o.id == id));
    });
  }

  Future<void> _showCreatePurchaseDialog() async {
    final supplierCodeController = TextEditingController();
    final supplierNameController = TextEditingController();
    final noteController = TextEditingController();
    String status = 'Đã nhập hàng';
    String? dialogError;
    final nextCode = StorageService.nextPurchaseOrderCode();
    final draftRows = <_DraftPurchaseRow>[
      _DraftPurchaseRow(),
    ];
    final existingSuppliers = _collectSuppliersFromOrders(_orders);

    double calculateDraftTotal() {
      return draftRows.fold(0.0, (sum, row) => sum + row.lineTotal);
    }

    Product? findByCode(String rawCode) {
      final q = rawCode.trim().toLowerCase();
      if (q.isEmpty) return null;
      for (final p in _products) {
        if (p.code.trim().toLowerCase() == q) return p;
      }
      return null;
    }

    Product? findByName(String rawName) {
      final q = rawName.trim().toLowerCase();
      if (q.isEmpty) return null;
      for (final p in _products) {
        if (p.name.trim().toLowerCase().contains(q)) return p;
      }
      return null;
    }

    List<_SupplierOption> filterSuppliers() {
      final codeQ = supplierCodeController.text.trim().toLowerCase();
      final nameQ = supplierNameController.text.trim().toLowerCase();
      return existingSuppliers.where((s) {
        final codeOk = codeQ.isEmpty || s.code.toLowerCase().contains(codeQ);
        final nameOk = nameQ.isEmpty || s.name.toLowerCase().contains(nameQ);
        return codeOk && nameOk;
      }).take(8).toList();
    }

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setStateDialog) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          title: Text('Tạo phiếu nhập hàng - $nextCode'),
          content: SizedBox(
            width: MediaQuery.sizeOf(dialogCtx).width * 0.88,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(dialogCtx).height * 0.72,
                maxWidth: 1120,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: supplierCodeController,
                      decoration: const InputDecoration(
                        labelText: 'Mã NCC',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setStateDialog(() => dialogError = null),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: supplierNameController,
                      decoration: const InputDecoration(
                        labelText: 'Nhà cung cấp',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setStateDialog(() => dialogError = null),
                    ),
                    if (filterSuppliers().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: filterSuppliers()
                              .map(
                                (s) => ActionChip(
                                  avatar: const Icon(Icons.store_mall_directory_outlined, size: 16),
                                  label: Text('${s.code} - ${s.name}'),
                                  onPressed: () {
                                    supplierCodeController.text = s.code;
                                    supplierNameController.text = s.name;
                                    setStateDialog(() => dialogError = null);
                                  },
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: status,
                      decoration: const InputDecoration(
                        labelText: 'Trạng thái',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Đã nhập hàng',
                          child: Text('Đã nhập hàng'),
                        ),
                        DropdownMenuItem(
                          value: 'Đang xử lý',
                          child: Text('Đang xử lý'),
                        ),
                      ],
                      onChanged: (value) {
                        setStateDialog(() {
                          status = value ?? 'Đã nhập hàng';
                          dialogError = null;
                        });
                      },
                    ),
                    if (dialogError != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red[200]!),
                        ),
                        child: Text(
                          dialogError!,
                          style: const TextStyle(color: Color(0xFFB71C1C), fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: 1060,
                        child: Column(
                          children: [
                            _buildDraftHeader(),
                            Container(
                              constraints: const BoxConstraints(maxHeight: 220),
                              decoration: BoxDecoration(
                                border: Border(
                                  left: BorderSide(color: Colors.grey[300]!),
                                  right: BorderSide(color: Colors.grey[300]!),
                                  bottom: BorderSide(color: Colors.grey[300]!),
                                ),
                              ),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: draftRows.length,
                                itemBuilder: (_, i) {
                                  final row = draftRows[i];
                                  return _buildDraftRow(
                                    row: row,
                                    index: i,
                                    onChanged: () => setStateDialog(() {}),
                                    onCodeSubmitted: () {
                                      final matched = findByCode(row.codeController.text);
                                      if (matched == null) return;
                                      row.productId = matched.id;
                                      row.nameController.text = matched.name;
                                      if (parseVndPrice(row.unitPriceController.text) == null ||
                                          parseVndPrice(row.unitPriceController.text) == 0) {
                                        row.unitPriceController.text = formatVndPrice(
                                          matched.costPrice > 0 ? matched.costPrice : matched.price,
                                        );
                                      }
                                      setStateDialog(() {});
                                    },
                                    onNameSubmitted: () {
                                      final matched = findByName(row.nameController.text);
                                      if (matched == null) return;
                                      row.productId = matched.id;
                                      row.codeController.text = matched.code;
                                      if (parseVndPrice(row.unitPriceController.text) == null ||
                                          parseVndPrice(row.unitPriceController.text) == 0) {
                                        row.unitPriceController.text = formatVndPrice(
                                          matched.costPrice > 0 ? matched.costPrice : matched.price,
                                        );
                                      }
                                      setStateDialog(() {});
                                    },
                                    onRemove: draftRows.length <= 1
                                        ? null
                                        : () {
                                            final removed = draftRows.removeAt(i);
                                            removed.dispose();
                                            setStateDialog(() {});
                                          },
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            draftRows.add(_DraftPurchaseRow());
                            setStateDialog(() {});
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Thêm dòng'),
                        ),
                        const Spacer(),
                        Text(
                          'Tổng tiền nhập: ${_formatNumber.format(calculateDraftTotal())}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0D47A1),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: noteController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Ghi chú (tuỳ chọn)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () async {
                final supplierCode = supplierCodeController.text.trim();
                final supplierName = supplierNameController.text.trim();
                final note = noteController.text.trim();

                if (supplierName.isEmpty) {
                  setStateDialog(() => dialogError = 'Vui lòng nhập tên nhà cung cấp.');
                  return;
                }

                final items = <PurchaseOrderItem>[];
                for (final row in draftRows) {
                  final code = row.codeController.text.trim();
                  final name = row.nameController.text.trim();
                  if (code.isEmpty && name.isEmpty) continue;
                  final qty = int.tryParse(
                        row.qtyController.text.replaceAll(RegExp(r'[^\d]'), ''),
                      ) ??
                      0;
                  if (qty <= 0) continue;
                  final unitPrice = parseVndPrice(row.unitPriceController.text) ?? 0;
                  final discount = parseVndPrice(row.discountController.text) ?? 0;
                  final matched = findByCode(code) ?? findByName(name);
                  items.add(
                    PurchaseOrderItem(
                      productId: matched?.id ?? row.productId,
                      productCode: matched?.code ?? code,
                      productName: matched?.name ?? name,
                      quantity: qty,
                      unitPrice: unitPrice,
                      discountAmount: discount,
                    ),
                  );
                }

                if (items.isEmpty) {
                  setStateDialog(() => dialogError = 'Vui lòng nhập ít nhất 1 dòng hàng hợp lệ (đủ mã/tên và số lượng > 0).');
                  return;
                }

                final amountDue = items.fold(0.0, (sum, i) => sum + i.lineTotal);
                final order = PurchaseOrder(
                  id: const Uuid().v4(),
                  code: nextCode,
                  supplierCode: supplierCode.isEmpty ? 'NCC0000' : supplierCode,
                  supplierName: supplierName,
                  amountDue: amountDue,
                  status: status,
                  createdAt: DateTime.now(),
                  note: note.isEmpty ? null : note,
                  items: items,
                );
                await StorageService.savePurchaseOrder(order);
                await StorageService.applyPurchaseOrderInventory(order);
                if (!mounted) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );

    for (final row in draftRows) {
      row.dispose();
    }

    if (created == true) {
      _loadOrders();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã lưu phiếu nhập hàng')),
      );
    }
  }

  Future<void> _showEditPurchaseDialog(PurchaseOrder editing) async {
    final supplierCodeController = TextEditingController(text: editing.supplierCode);
    final supplierNameController = TextEditingController(text: editing.supplierName);
    final noteController = TextEditingController(text: editing.note ?? '');
    String status = editing.status;
    String? dialogError;
    final code = editing.code;
    final draftRows = editing.items.isNotEmpty
        ? editing.items
            .map(
              (e) => _DraftPurchaseRow(
                productId: e.productId,
                code: e.productCode,
                name: e.productName,
                qty: e.quantity.toString(),
                unitPrice: formatVndPrice(e.unitPrice),
                discount: formatVndPrice(e.discountAmount),
              ),
            )
            .toList()
        : <_DraftPurchaseRow>[_DraftPurchaseRow()];
    final existingSuppliers = _collectSuppliersFromOrders(_orders);

    double calculateDraftTotal() {
      return draftRows.fold(0.0, (sum, row) => sum + row.lineTotal);
    }

    Product? findByCode(String rawCode) {
      final q = rawCode.trim().toLowerCase();
      if (q.isEmpty) return null;
      for (final p in _products) {
        if (p.code.trim().toLowerCase() == q) return p;
      }
      return null;
    }

    Product? findByName(String rawName) {
      final q = rawName.trim().toLowerCase();
      if (q.isEmpty) return null;
      for (final p in _products) {
        if (p.name.trim().toLowerCase().contains(q)) return p;
      }
      return null;
    }

    List<_SupplierOption> filterSuppliers() {
      final codeQ = supplierCodeController.text.trim().toLowerCase();
      final nameQ = supplierNameController.text.trim().toLowerCase();
      return existingSuppliers.where((s) {
        final codeOk = codeQ.isEmpty || s.code.toLowerCase().contains(codeQ);
        final nameOk = nameQ.isEmpty || s.name.toLowerCase().contains(nameQ);
        return codeOk && nameOk;
      }).take(8).toList();
    }

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setStateDialog) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          title: Text('Sửa phiếu nhập hàng - $code'),
          content: SizedBox(
            width: MediaQuery.sizeOf(dialogCtx).width * 0.88,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(dialogCtx).height * 0.72,
                maxWidth: 1120,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: supplierCodeController,
                      decoration: const InputDecoration(
                        labelText: 'Mã NCC',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setStateDialog(() => dialogError = null),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: supplierNameController,
                      decoration: const InputDecoration(
                        labelText: 'Nhà cung cấp',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setStateDialog(() => dialogError = null),
                    ),
                    if (filterSuppliers().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: filterSuppliers()
                              .map(
                                (s) => ActionChip(
                                  avatar: const Icon(Icons.store_mall_directory_outlined, size: 16),
                                  label: Text('${s.code} - ${s.name}'),
                                  onPressed: () {
                                    supplierCodeController.text = s.code;
                                    supplierNameController.text = s.name;
                                    setStateDialog(() => dialogError = null);
                                  },
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: status,
                      decoration: const InputDecoration(
                        labelText: 'Trạng thái',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Đã nhập hàng',
                          child: Text('Đã nhập hàng'),
                        ),
                        DropdownMenuItem(
                          value: 'Đang xử lý',
                          child: Text('Đang xử lý'),
                        ),
                      ],
                      onChanged: (value) {
                        setStateDialog(() {
                          status = value ?? 'Đã nhập hàng';
                          dialogError = null;
                        });
                      },
                    ),
                    if (dialogError != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red[200]!),
                        ),
                        child: Text(
                          dialogError!,
                          style: const TextStyle(color: Color(0xFFB71C1C), fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: 1060,
                        child: Column(
                          children: [
                            _buildDraftHeader(),
                            Container(
                              constraints: const BoxConstraints(maxHeight: 220),
                              decoration: BoxDecoration(
                                border: Border(
                                  left: BorderSide(color: Colors.grey[300]!),
                                  right: BorderSide(color: Colors.grey[300]!),
                                  bottom: BorderSide(color: Colors.grey[300]!),
                                ),
                              ),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: draftRows.length,
                                itemBuilder: (_, i) {
                                  final row = draftRows[i];
                                  return _buildDraftRow(
                                    row: row,
                                    index: i,
                                    onChanged: () => setStateDialog(() {}),
                                    onCodeSubmitted: () {
                                      final matched = findByCode(row.codeController.text);
                                      if (matched == null) return;
                                      row.productId = matched.id;
                                      row.nameController.text = matched.name;
                                      if (parseVndPrice(row.unitPriceController.text) == null ||
                                          parseVndPrice(row.unitPriceController.text) == 0) {
                                        row.unitPriceController.text = formatVndPrice(
                                          matched.costPrice > 0 ? matched.costPrice : matched.price,
                                        );
                                      }
                                      setStateDialog(() {});
                                    },
                                    onNameSubmitted: () {
                                      final matched = findByName(row.nameController.text);
                                      if (matched == null) return;
                                      row.productId = matched.id;
                                      row.codeController.text = matched.code;
                                      if (parseVndPrice(row.unitPriceController.text) == null ||
                                          parseVndPrice(row.unitPriceController.text) == 0) {
                                        row.unitPriceController.text = formatVndPrice(
                                          matched.costPrice > 0 ? matched.costPrice : matched.price,
                                        );
                                      }
                                      setStateDialog(() {});
                                    },
                                    onRemove: draftRows.length <= 1
                                        ? null
                                        : () {
                                            final removed = draftRows.removeAt(i);
                                            removed.dispose();
                                            setStateDialog(() {});
                                          },
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            draftRows.add(_DraftPurchaseRow());
                            setStateDialog(() {});
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Thêm dòng'),
                        ),
                        const Spacer(),
                        Text(
                          'Tổng tiền nhập: ${_formatNumber.format(calculateDraftTotal())}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0D47A1),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: noteController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Ghi chú (tuỳ chọn)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () async {
                final supplierCode = supplierCodeController.text.trim();
                final supplierName = supplierNameController.text.trim();
                final note = noteController.text.trim();

                if (supplierName.isEmpty) {
                  setStateDialog(() => dialogError = 'Vui lòng nhập tên nhà cung cấp.');
                  return;
                }

                final items = <PurchaseOrderItem>[];
                for (final row in draftRows) {
                  final c = row.codeController.text.trim();
                  final n = row.nameController.text.trim();
                  if (c.isEmpty && n.isEmpty) continue;
                  final qty = int.tryParse(row.qtyController.text.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
                  if (qty <= 0) continue;
                  final unitPrice = parseVndPrice(row.unitPriceController.text) ?? 0;
                  final discount = parseVndPrice(row.discountController.text) ?? 0;
                  final matched = findByCode(c) ?? findByName(n);
                  items.add(
                    PurchaseOrderItem(
                      productId: matched?.id ?? row.productId,
                      productCode: matched?.code ?? c,
                      productName: matched?.name ?? n,
                      quantity: qty,
                      unitPrice: unitPrice,
                      discountAmount: discount,
                    ),
                  );
                }

                if (items.isEmpty) {
                  setStateDialog(() => dialogError = 'Vui lòng nhập ít nhất 1 dòng hàng hợp lệ (đủ mã/tên và số lượng > 0).');
                  return;
                }

                final amountDue = items.fold(0.0, (sum, i) => sum + i.lineTotal);
                final updatedOrder = PurchaseOrder(
                  id: editing.id,
                  code: editing.code,
                  supplierCode: supplierCode.isEmpty ? 'NCC0000' : supplierCode,
                  supplierName: supplierName,
                  amountDue: amountDue,
                  status: status,
                  createdAt: editing.createdAt,
                  note: note.isEmpty ? null : note,
                  items: items,
                );
                await StorageService.rollbackPurchaseOrderInventory(editing);
                await StorageService.updatePurchaseOrder(updatedOrder);
                await StorageService.applyPurchaseOrderInventory(updatedOrder);
                if (!mounted) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('Cập nhật'),
            ),
          ],
        ),
      ),
    );

    for (final row in draftRows) {
      row.dispose();
    }
    if (updated == true) {
      _loadOrders();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã cập nhật phiếu ${editing.code}')),
      );
    }
  }

  String _normalizeSearchText(String input) {
    var s = input.trim().toLowerCase();
    const replacements = <String, String>{
      'à': 'a',
      'á': 'a',
      'ạ': 'a',
      'ả': 'a',
      'ã': 'a',
      'â': 'a',
      'ầ': 'a',
      'ấ': 'a',
      'ậ': 'a',
      'ẩ': 'a',
      'ẫ': 'a',
      'ă': 'a',
      'ằ': 'a',
      'ắ': 'a',
      'ặ': 'a',
      'ẳ': 'a',
      'ẵ': 'a',
      'đ': 'd',
      'è': 'e',
      'é': 'e',
      'ẹ': 'e',
      'ẻ': 'e',
      'ẽ': 'e',
      'ê': 'e',
      'ề': 'e',
      'ế': 'e',
      'ệ': 'e',
      'ể': 'e',
      'ễ': 'e',
      'ì': 'i',
      'í': 'i',
      'ị': 'i',
      'ỉ': 'i',
      'ĩ': 'i',
      'ò': 'o',
      'ó': 'o',
      'ọ': 'o',
      'ỏ': 'o',
      'õ': 'o',
      'ô': 'o',
      'ồ': 'o',
      'ố': 'o',
      'ộ': 'o',
      'ổ': 'o',
      'ỗ': 'o',
      'ơ': 'o',
      'ờ': 'o',
      'ớ': 'o',
      'ợ': 'o',
      'ở': 'o',
      'ỡ': 'o',
      'ù': 'u',
      'ú': 'u',
      'ụ': 'u',
      'ủ': 'u',
      'ũ': 'u',
      'ư': 'u',
      'ừ': 'u',
      'ứ': 'u',
      'ự': 'u',
      'ử': 'u',
      'ữ': 'u',
      'ỳ': 'y',
      'ý': 'y',
      'ỵ': 'y',
      'ỷ': 'y',
      'ỹ': 'y',
    };
    replacements.forEach((k, v) {
      s = s.replaceAll(k, v);
    });
    return s;
  }

  bool _containsNormalized(String source, String query) {
    if (query.trim().isEmpty) return true;
    return _normalizeSearchText(source).contains(_normalizeSearchText(query));
  }

  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime _endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  String get _rangeLabel {
    if (_selectedRange == null) return 'Tất cả thời gian';
    return '${_formatDay.format(_selectedRange!.start)} - ${_formatDay.format(_selectedRange!.end)}';
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _selectedRange ??
          DateTimeRange(
            start: _startOfDay(now),
            end: _startOfDay(now),
          ),
      helpText: 'Chọn khoảng ngày',
      saveText: 'Áp dụng',
      cancelText: 'Hủy',
      confirmText: 'Chọn',
      locale: const Locale('vi', 'VN'),
    );
    if (picked == null) return;
    setState(() => _selectedRange = picked);
  }

  void _setQuickRangeToday() {
    final today = _startOfDay(DateTime.now());
    setState(() => _selectedRange = DateTimeRange(start: today, end: today));
  }

  void _setQuickRangeLast7Days() {
    final today = _startOfDay(DateTime.now());
    final start = today.subtract(const Duration(days: 6));
    setState(() => _selectedRange = DateTimeRange(start: start, end: today));
  }

  void _setQuickRangeThisMonth() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = _startOfDay(now);
    setState(() => _selectedRange = DateTimeRange(start: start, end: end));
  }

  void _clearRangeFilter() {
    setState(() => _selectedRange = null);
  }

  List<PurchaseOrder> get _filteredOrders {
    final query = _searchController.text.trim();
    return _orders.where((order) {
      if (_selectedRange != null) {
        final start = _startOfDay(_selectedRange!.start);
        final end = _endOfDay(_selectedRange!.end);
        final inRange = !order.createdAt.isBefore(start) && !order.createdAt.isAfter(end);
        if (!inRange) return false;
      }

      if (query.isEmpty) return true;
      final searchable = StringBuffer()
        ..write(order.code)
        ..write(' ')
        ..write(order.supplierCode)
        ..write(' ')
        ..write(order.supplierName);
      for (final item in order.items) {
        searchable
          ..write(' ')
          ..write(item.productCode)
          ..write(' ')
          ..write(item.productName);
      }
      return _containsNormalized(searchable.toString(), query);
    }).toList();
  }

  bool get _allSelected {
    final visible = _filteredOrders;
    return visible.isNotEmpty && visible.every((o) => _selectedIds.contains(o.id));
  }
  double get _totalAmountDue => _filteredOrders.fold(0.0, (sum, order) => sum + order.amountDue);

  List<PurchaseOrder> get _selectedOrders {
    if (_selectedIds.isEmpty) return _filteredOrders;
    return _orders.where((o) => _selectedIds.contains(o.id)).toList();
  }

  Future<void> _exportOrders() async {
    final exporting = _selectedOrders;
    if (exporting.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không có dữ liệu để export')),
      );
      return;
    }
    try {
      final path = await PurchaseExportService.exportToExcel(exporting);
      if (!mounted) return;
      if (path == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã hủy export hoặc chưa chọn nơi lưu file')),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã export file: $path')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export thất bại: $e')),
      );
    }
  }

  void _showOrderDetail(PurchaseOrder order) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Chi tiết ${order.code}'),
        content: SizedBox(
          width: 900,
          child: order.items.isEmpty
              ? const Text('Phiếu này chưa có chi tiết dòng hàng')
              : SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildReadOnlyHeader(),
                      ...order.items.map(_buildReadOnlyRow),
                    ],
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Future<void> _printOrderA5(PurchaseOrder order) async {
    await PrintService.printPurchaseOrderA5(
      context: context,
      order: order,
      creatorName: 'Nhân viên',
    );
  }

  Future<void> _deleteOrder(PurchaseOrder order) async {
    var rollbackInventory = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('Xóa phiếu nhập hàng'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Bạn có chắc muốn xóa phiếu ${order.code}?'),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: rollbackInventory,
                onChanged: (v) => setStateDialog(() => rollbackInventory = v ?? true),
                contentPadding: EdgeInsets.zero,
                title: const Text('Hoàn tồn kho theo phiếu này'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red[700]),
              child: const Text('Xóa'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    if (rollbackInventory) {
      await StorageService.rollbackPurchaseOrderInventory(order);
    }
    await StorageService.deletePurchaseOrder(order.id);
    _loadOrders();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã xóa phiếu ${order.code}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nhập hàng'),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _exportOrders,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white),
                  ),
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Export'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _showCreatePurchaseDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('Tạo phiếu nhập'),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Text(
                    'Tổng cần trả NCC',
                    style: TextStyle(
                      color: Colors.grey[800],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatNumber.format(_totalAmountDue),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0D47A1),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Tìm theo mã phiếu, mã/tên hàng, mã/tên NCC',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Xóa tìm kiếm',
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.close, size: 18),
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.today, size: 18),
                        label: const Text('Hôm nay'),
                        onPressed: _setQuickRangeToday,
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.date_range, size: 18),
                        label: const Text('7 ngày'),
                        onPressed: _setQuickRangeLast7Days,
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.calendar_month, size: 18),
                        label: const Text('Tháng này'),
                        onPressed: _setQuickRangeThisMonth,
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.edit_calendar, size: 18),
                        label: const Text('Chọn ngày'),
                        onPressed: _pickDateRange,
                      ),
                      if (_selectedRange != null)
                        ActionChip(
                          avatar: const Icon(Icons.clear, size: 18),
                          label: const Text('Bỏ lọc'),
                          onPressed: _clearRangeFilter,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Khoảng chọn: $_rangeLabel',
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _orders.isEmpty
                  ? Center(
                      child: Text(
                        'Chưa có phiếu nhập hàng',
                        style: TextStyle(color: Colors.grey[600], fontSize: 16),
                      ),
                    )
                  : _filteredOrders.isEmpty
                      ? Center(
                          child: Text(
                            'Không tìm thấy phiếu nhập phù hợp',
                            style: TextStyle(color: Colors.grey[600], fontSize: 16),
                          ),
                        )
                  : Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          child: DataTable(
                            headingRowColor: WidgetStatePropertyAll(Colors.blue[50]),
                            columnSpacing: 22,
                            columns: [
                              DataColumn(
                                label: Row(
                                  children: [
                                    Checkbox(
                                      value: _allSelected,
                                      onChanged: (value) {
                                        final visible = _filteredOrders;
                                        setState(() {
                                          if (value == true) {
                                            _selectedIds
                                              ..clear()
                                              ..addAll(visible.map((o) => o.id));
                                          } else {
                                            _selectedIds.removeWhere((id) => visible.any((o) => o.id == id));
                                          }
                                        });
                                      },
                                    ),
                                    const Icon(Icons.star_border, size: 18),
                                  ],
                                ),
                              ),
                              const DataColumn(label: Text('Mã nhập hàng')),
                              const DataColumn(label: Text('Thời gian')),
                              const DataColumn(label: Text('Mã NCC')),
                              const DataColumn(label: Text('Nhà cung cấp')),
                              const DataColumn(
                                label: Align(
                                  alignment: Alignment.centerRight,
                                  child: Text('Cần trả NCC'),
                                ),
                                numeric: true,
                              ),
                              const DataColumn(label: Text('Trạng thái')),
                              const DataColumn(label: Text('Thao tác')),
                            ],
                            rows: _filteredOrders.map((order) {
                              final selected = _selectedIds.contains(order.id);
                              return DataRow(
                                selected: selected,
                                onSelectChanged: (value) {
                                  setState(() {
                                    if (value == true) {
                                      _selectedIds.add(order.id);
                                    } else {
                                      _selectedIds.remove(order.id);
                                    }
                                  });
                                },
                                cells: [
                                  DataCell(
                                    Row(
                                      children: [
                                        Checkbox(
                                          value: selected,
                                          onChanged: (value) {
                                            setState(() {
                                              if (value == true) {
                                                _selectedIds.add(order.id);
                                              } else {
                                                _selectedIds.remove(order.id);
                                              }
                                            });
                                          },
                                        ),
                                        const Icon(Icons.star_border, size: 18, color: Colors.grey),
                                      ],
                                    ),
                                  ),
                                  DataCell(Text(order.code)),
                                  DataCell(Text(_formatDate.format(order.createdAt))),
                                  DataCell(Text(order.supplierCode)),
                                  DataCell(
                                    SizedBox(
                                      width: 220,
                                      child: Text(
                                        order.supplierName,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: Text(_formatNumber.format(order.amountDue)),
                                    ),
                                  ),
                                  DataCell(_buildStatusChip(order.status)),
                                  DataCell(
                                    PopupMenuButton<String>(
                                      tooltip: 'Thao tác',
                                      onSelected: (value) async {
                                        if (value == 'detail') {
                                          _showOrderDetail(order);
                                          return;
                                        }
                                        if (value == 'edit') {
                                          await _showEditPurchaseDialog(order);
                                          return;
                                        }
                                        if (value == 'print') {
                                          await _printOrderA5(order);
                                          return;
                                        }
                                        if (value == 'delete') {
                                          await _deleteOrder(order);
                                        }
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem<String>(
                                          value: 'detail',
                                          child: ListTile(
                                            leading: Icon(Icons.visibility_outlined),
                                            title: Text('Xem chi tiết'),
                                          ),
                                        ),
                                        PopupMenuItem<String>(
                                          value: 'edit',
                                          child: ListTile(
                                            leading: Icon(Icons.edit_outlined),
                                            title: Text('Sửa phiếu'),
                                          ),
                                        ),
                                        PopupMenuItem<String>(
                                          value: 'print',
                                          child: ListTile(
                                            leading: Icon(Icons.print_outlined),
                                            title: Text('In phiếu A5'),
                                          ),
                                        ),
                                        PopupMenuItem<String>(
                                          value: 'delete',
                                          child: ListTile(
                                            leading: Icon(Icons.delete_outline, color: Colors.red),
                                            title: Text('Xóa phiếu'),
                                          ),
                                        ),
                                      ],
                                      child: const Icon(Icons.more_vert),
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDraftHeader() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.blue[50],
        border: Border.all(color: Colors.grey[300]!),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      child: const Row(
        children: [
          SizedBox(width: 150, child: Text('Mã hàng', style: TextStyle(fontWeight: FontWeight.w700))),
          SizedBox(width: 8),
          SizedBox(width: 230, child: Text('Tên hàng', style: TextStyle(fontWeight: FontWeight.w700))),
          SizedBox(width: 8),
          SizedBox(width: 90, child: Text('Số lượng', style: TextStyle(fontWeight: FontWeight.w700))),
          SizedBox(width: 8),
          SizedBox(width: 120, child: Text('Đơn giá', style: TextStyle(fontWeight: FontWeight.w700))),
          SizedBox(width: 8),
          SizedBox(width: 120, child: Text('Giảm giá', style: TextStyle(fontWeight: FontWeight.w700))),
          SizedBox(width: 8),
          SizedBox(width: 120, child: Text('Giá nhập', style: TextStyle(fontWeight: FontWeight.w700))),
          SizedBox(width: 8),
          SizedBox(width: 120, child: Text('Thành tiền', style: TextStyle(fontWeight: FontWeight.w700))),
          SizedBox(width: 36),
        ],
      ),
    );
  }

  Widget _buildDraftRow({
    required _DraftPurchaseRow row,
    required int index,
    required VoidCallback onChanged,
    required VoidCallback onCodeSubmitted,
    required VoidCallback onNameSubmitted,
    required VoidCallback? onRemove,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.grey[200]!),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: TextField(
              controller: row.codeController,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Tìm mã hàng',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => onChanged(),
              onSubmitted: (_) => onCodeSubmitted(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 230,
            child: TextField(
              controller: row.nameController,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Tìm tên hàng',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => onChanged(),
              onSubmitted: (_) => onNameSubmitted(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            child: TextField(
              controller: row.qtyController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => onChanged(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: TextField(
              controller: row.unitPriceController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                VndPriceInputFormatter(),
              ],
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => onChanged(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: TextField(
              controller: row.discountController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                VndPriceInputFormatter(),
              ],
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => onChanged(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                _formatNumber.format(row.importPrice),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                _formatNumber.format(row.lineTotal),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          SizedBox(
            width: 36,
            child: IconButton(
              tooltip: 'Xóa dòng ${index + 1}',
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadOnlyHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        children: [
          Expanded(flex: 2, child: Text('Mã hàng', style: TextStyle(fontWeight: FontWeight.w700))),
          Expanded(flex: 4, child: Text('Tên hàng', style: TextStyle(fontWeight: FontWeight.w700))),
          Expanded(child: Text('SL', style: TextStyle(fontWeight: FontWeight.w700))),
          Expanded(child: Text('Đơn giá', style: TextStyle(fontWeight: FontWeight.w700))),
          Expanded(child: Text('Giảm', style: TextStyle(fontWeight: FontWeight.w700))),
          Expanded(child: Text('Giá nhập', style: TextStyle(fontWeight: FontWeight.w700))),
          Expanded(child: Text('Thành tiền', style: TextStyle(fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  Widget _buildReadOnlyRow(PurchaseOrderItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(item.productCode)),
          Expanded(flex: 4, child: Text(item.productName)),
          Expanded(child: Text(item.quantity.toString())),
          Expanded(child: Text(_formatNumber.format(item.unitPrice))),
          Expanded(child: Text(_formatNumber.format(item.discountAmount))),
          Expanded(child: Text(_formatNumber.format(item.importPrice))),
          Expanded(
            child: Text(
              _formatNumber.format(item.lineTotal),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  List<_SupplierOption> _collectSuppliersFromOrders(List<PurchaseOrder> orders) {
    final byName = <String, _SupplierOption>{};
    for (final order in orders) {
      final name = order.supplierName.trim();
      if (name.isEmpty) continue;
      final key = name.toLowerCase();
      if (!byName.containsKey(key)) {
        byName[key] = _SupplierOption(
          code: order.supplierCode.trim().isEmpty ? 'NCC0000' : order.supplierCode.trim(),
          name: name,
        );
      }
    }
    final list = byName.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  Widget _buildStatusChip(String status) {
    final isDone = status == 'Đã nhập hàng';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDone ? const Color(0xFFE8F5E9) : const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: isDone ? const Color(0xFF2E7D32) : const Color(0xFFF57F17),
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _SupplierOption {
  final String code;
  final String name;

  const _SupplierOption({
    required this.code,
    required this.name,
  });
}

class _DraftPurchaseRow {
  String productId;
  final TextEditingController codeController;
  final TextEditingController nameController;
  final TextEditingController qtyController;
  final TextEditingController unitPriceController;
  final TextEditingController discountController;

  _DraftPurchaseRow({
    this.productId = '',
    String code = '',
    String name = '',
    String qty = '1',
    String unitPrice = '',
    String discount = '0',
  })  : codeController = TextEditingController(text: code),
        nameController = TextEditingController(text: name),
        qtyController = TextEditingController(text: qty),
        unitPriceController = TextEditingController(text: unitPrice),
        discountController = TextEditingController(text: discount);

  double get unitPrice => parseVndPrice(unitPriceController.text) ?? 0;
  double get discount => parseVndPrice(discountController.text) ?? 0;
  int get quantity => int.tryParse(qtyController.text.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
  double get importPrice => (unitPrice - discount).clamp(0, double.infinity).toDouble();
  double get lineTotal => importPrice * quantity;

  void dispose() {
    codeController.dispose();
    nameController.dispose();
    qtyController.dispose();
    unitPriceController.dispose();
    discountController.dispose();
  }
}
