import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/invoice.dart';
import '../services/storage_service.dart';
import '../services/print_service.dart';

class InvoicesScreen extends StatefulWidget {
  final bool isActive;

  const InvoicesScreen({super.key, this.isActive = true});

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  List<Invoice> _invoices = [];
  final _formatCurrency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫');
  final _formatDate = DateFormat('dd/MM/yyyy HH:mm');
  final _formatDay = DateFormat('dd/MM/yyyy');
  DateTimeRange? _selectedRange;

  @override
  void initState() {
    super.initState();
    _loadInvoices();
  }

  @override
  void didUpdateWidget(covariant InvoicesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _loadInvoices();
    }
  }

  void _loadInvoices() {
    setState(() {
      _invoices = StorageService.getInvoices();
    });
  }

  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime _endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  List<Invoice> get _filteredInvoices {
    if (_selectedRange == null) return _invoices;
    final start = _startOfDay(_selectedRange!.start);
    final end = _endOfDay(_selectedRange!.end);
    return _invoices
        .where((inv) =>
            !inv.createdAt.isBefore(start) && !inv.createdAt.isAfter(end))
        .toList();
  }

  double get _selectedRevenue =>
      _filteredInvoices.fold(0.0, (sum, inv) => sum + inv.total);

  Map<DateTime, double> get _revenueByDay {
    final result = <DateTime, double>{};
    for (final inv in _filteredInvoices) {
      final key = _startOfDay(inv.createdAt);
      result[key] = (result[key] ?? 0) + inv.total;
    }
    final entries = result.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    return Map<DateTime, double>.fromEntries(entries);
  }

  String get _rangeLabel {
    if (_selectedRange == null) return 'Tất cả thời gian';
    final start = _formatDay.format(_selectedRange!.start);
    final end = _formatDay.format(_selectedRange!.end);
    return '$start - $end';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lịch sử hoá đơn'),
        backgroundColor: const Color(0xFF6A1B9A),
        foregroundColor: Colors.white,
      ),
      body: _invoices.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 80,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Chưa có hoá đơn nào',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () async => _loadInvoices(),
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _filteredInvoices.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _buildFilterAndRevenueCard();
                  }
                  final inv = _filteredInvoices[index - 1];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 2,
                    child: ExpansionTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            const Color(0xFF6A1B9A).withOpacity(0.2),
                        child: const Icon(
                          Icons.receipt,
                          color: Color(0xFF6A1B9A),
                        ),
                      ),
                      title: Text(
                        '#${inv.id.substring(0, 8).toUpperCase()}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      subtitle: Text(_formatDate.format(inv.createdAt)),
                      trailing: Text(
                        _formatCurrency.format(inv.total),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF6A1B9A),
                          fontSize: 16,
                        ),
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ...inv.items.map(
                                (item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${item.productName} x${item.quantity}',
                                        ),
                                      ),
                                      Text(
                                        _formatCurrency.format(item.total),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const Divider(),
                              if (inv.discountAmount > 0)
                                _buildRow('Giảm giá:',
                                    '- ${_formatCurrency.format(inv.discountAmount)}'),
                              if (inv.customerName != null && inv.customerName!.trim().isNotEmpty)
                                _buildRow('Khách hàng:', inv.customerName!.trim()),
                              _buildRow('Tổng cộng:',
                                  _formatCurrency.format(inv.total),
                                  bold: true),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    await PrintService.printInvoice(
                                      context: context,
                                      items: inv.items,
                                      subtotal: inv.subtotal,
                                      discountAmount: inv.discountAmount,
                                      total: inv.total,
                                      invoiceId: inv.id,
                                      createdAt: inv.createdAt,
                                      customerName: inv.customerName,
                                    );
                                  },
                                  icon: const Icon(Icons.print),
                                  label: const Text('In lại hoá đơn'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }

  Widget _buildFilterAndRevenueCard() {
    final byDayEntries = _revenueByDay.entries.toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            const SizedBox(height: 12),
            Text(
              'Khoảng chọn: $_rangeLabel',
              style: TextStyle(
                color: Colors.grey[700],
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            _buildRow(
              'Tổng doanh thu:',
              _formatCurrency.format(_selectedRevenue),
              bold: true,
            ),
            const SizedBox(height: 8),
            Text(
              'Doanh thu theo ngày đã chọn',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 6),
            if (byDayEntries.isEmpty)
              Text(
                'Không có dữ liệu doanh thu trong khoảng này',
                style: TextStyle(color: Colors.grey[600]),
              )
            else
              ...byDayEntries.map(
                (e) => _buildRow(
                  _formatDay.format(e.key),
                  _formatCurrency.format(e.value),
                ),
              ),
            if (_filteredInvoices.isEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Không có hoá đơn trong ngày đã chọn',
                style: TextStyle(
                  color: Colors.grey[700],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : null,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : null,
              color: bold ? const Color(0xFF6A1B9A) : null,
            ),
          ),
        ],
      ),
    );
  }
}
