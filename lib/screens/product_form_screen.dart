import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../models/product.dart';
import '../services/storage_service.dart';
import '../utils/price_validator.dart';
import '../utils/vnd_input_formatter.dart';

class ProductFormScreen extends StatefulWidget {
  final Product? product;

  const ProductFormScreen({super.key, this.product});

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _codeController;
  late TextEditingController _priceController;
  late TextEditingController _costPriceController;
  late TextEditingController _stockController;
  late TextEditingController _unitController;
  late TextEditingController _imagePathController;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _isEditing = widget.product != null;
    _nameController = TextEditingController(text: widget.product?.name ?? '');
    _codeController = TextEditingController(text: widget.product?.code ?? '');
    _priceController = TextEditingController(
      text: _formatPriceForDisplay(widget.product?.price),
    );
    _costPriceController = TextEditingController(
      text: _formatPriceForDisplay(widget.product?.costPrice),
    );
    _stockController = TextEditingController(
      text: widget.product?.stock.toString() ?? '0',
    );
    _unitController = TextEditingController(text: widget.product?.unit ?? 'cái');
    _imagePathController = TextEditingController(text: widget.product?.imagePath ?? '');
  }

  String _formatPriceForDisplay(double? value) {
    return formatVndPrice(value);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _priceController.dispose();
    _costPriceController.dispose();
    _stockController.dispose();
    _unitController.dispose();
    _imagePathController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final product = Product(
      id: widget.product?.id ?? const Uuid().v4(),
      name: _nameController.text.trim(),
      code: _codeController.text.trim(),
      price: parseVndPrice(_priceController.text) ?? 0,
      costPrice: parseVndPrice(_costPriceController.text) ?? 0,
      stock: int.tryParse(_stockController.text) ?? 0,
      unit: _unitController.text.trim().isEmpty ? 'cái' : _unitController.text.trim(),
      imagePath: _imagePathController.text.trim().isEmpty ? null : _imagePathController.text.trim(),
    );

    if (_isEditing) {
      await StorageService.updateProduct(product);
    } else {
      await StorageService.addProduct(product);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Chỉnh sửa sản phẩm' : 'Thêm sản phẩm'),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Tên sản phẩm',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.shopping_bag),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Nhập tên sản phẩm' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _codeController,
              decoration: const InputDecoration(
                labelText: 'Mã sản phẩm',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.qr_code),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Nhập mã sản phẩm' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _priceController,
              decoration: const InputDecoration(
                labelText: 'Giá bán (VNĐ)',
                hintText: 'VD: 150.000',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.sell),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, VndPriceInputFormatter()],
              validator: (v) => validateVndPrice(v, fieldName: 'Giá bán'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _costPriceController,
              decoration: const InputDecoration(
                labelText: 'Giá nhập (VNĐ) - tùy chọn',
                hintText: 'VD: 12.222.222',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.shopping_cart),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, VndPriceInputFormatter()],
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                return validateVndPrice(v, fieldName: 'Giá nhập');
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _stockController,
              decoration: const InputDecoration(
                labelText: 'Số lượng tồn kho',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.inventory),
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Nhập số lượng';
                if (int.tryParse(v) == null) return 'Số lượng không hợp lệ';
                if ((int.tryParse(v) ?? 0) < 0) return 'Số lượng phải >= 0';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _unitController,
              decoration: const InputDecoration(
                labelText: 'Đơn vị (cái, hộp, kg...)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.straighten),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _imagePathController,
              decoration: const InputDecoration(
                labelText: 'URL hình ảnh (tùy chọn)',
                hintText: 'https://...',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.image),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(_isEditing ? 'Cập nhật' : 'Lưu sản phẩm'),
            ),
          ],
        ),
      ),
    );
  }
}
