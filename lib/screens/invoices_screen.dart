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
                itemCount: _invoices.length,
                itemBuilder: (context, index) {
                  final inv = _invoices[index];
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
