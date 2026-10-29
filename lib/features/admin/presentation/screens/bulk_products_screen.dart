import 'package:flutter/material.dart';

import '../../../../core/widgets/app_image.dart';
import '../../data/admin_files.dart';
import '../../data/admin_repository.dart';
import '../../../products/domain/models/category_model.dart';
import '../widgets/admin_product_fields.dart';

class _ProductDraft {
  final key = UniqueKey();
  final controllers = <String, TextEditingController>{
    for (final entry in {
      'img': '',
      'name': '',
      'sku': '',
      'category': '',
      'brand': '',
      'purchase_price': '0',
      'price': '0',
      'mrp': '0',
      'moq': '1',
      'stock_quantity': '50',
      'desc': '',
    }.entries)
      entry.key: TextEditingController(text: entry.value),
  };
  String get sku => controllers['sku']!.text.trim().toUpperCase();
  Map<String, dynamic> toPayload() => {
    for (final entry in controllers.entries)
      entry.key:
          [
            'purchase_price',
            'price',
            'mrp',
            'stock_quantity',
          ].contains(entry.key)
          ? num.parse(entry.value.text.trim())
          : entry.value.text.trim(),
    'status': 'active',
  };
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
  }
}

class BulkProductsScreen extends StatefulWidget {
  final AdminRepository repository;
  final List<CategoryModel> categories;
  final VoidCallback onSaved;
  const BulkProductsScreen({
    super.key,
    required this.repository,
    required this.onSaved,
    this.categories = const [],
  });
  @override
  State<BulkProductsScreen> createState() => _BulkProductsScreenState();
}

class _BulkProductsScreenState extends State<BulkProductsScreen> {
  final _form = GlobalKey<FormState>();
  final _rows = [_ProductDraft()];
  final _retiredRows = <_ProductDraft>[];
  bool _saving = false;
  String? _error;
  int _savedCount = 0;

  @override
  void dispose() {
    for (final row in [..._rows, ..._retiredRows]) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _saveAll() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) {
      setState(() => _error = 'Check the highlighted fields in every product.');
      return;
    }
    final skus = <String>{};
    for (final row in _rows) {
      if (!skus.add(row.sku)) {
        setState(
          () =>
              _error = 'Each product needs a unique SKU. Duplicate: ${row.sku}',
        );
        return;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.repository.request(
        'products/bulk',
        method: 'POST',
        data: {'products': _rows.map((row) => row.toPayload()).toList()},
      );
      if (!mounted) return;
      final imported = (result['imported'] as List? ?? [])
          .whereType<Map>()
          .map((product) => '${product['sku']}'.toUpperCase())
          .toSet();
      final skipped = (result['skipped'] as List? ?? [])
          .whereType<Map>()
          .toList();
      final count =
          (result['importedCount'] as num?)?.toInt() ?? imported.length;
      if (count > 0) {
        _savedCount += count;
        widget.onSaved();
      }
      if (count == _rows.length && skipped.isEmpty) {
        setState(() => _saving = false);
        Navigator.pop(context, _savedCount);
        return;
      }
      setState(() {
        final savedRows = _rows
            .where((row) => imported.contains(row.sku))
            .toList();
        _rows.removeWhere(savedRows.contains);
        _retiredRows.addAll(savedRows);
        _error = [
          count > 0
              ? '$count products saved. Resolve the remaining products below.'
              : 'No products were saved to MySQL.',
          ...skipped.map(
            (failure) =>
                '${failure['sku'] ?? 'Product'}: ${failure['reason'] ?? 'Could not save'}',
          ),
        ].join('\n');
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        if (_error != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(_error!.split('\n').first)));
        }
      }
    }
  }

  Widget _row(_ProductDraft row, int index) => Card(
    key: row.key,
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Product ${index + 1}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (_rows.length > 1)
                IconButton(
                  tooltip: 'Remove product ${index + 1}',
                  onPressed: () => setState(() {
                    _rows.remove(row);
                    _retiredRows.add(row);
                  }),
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: row.controllers['img']!,
            builder: (context, value, child) => value.text.trim().isEmpty
                ? const SizedBox.shrink()
                : Container(
                    height: 140,
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    margin: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: AppImage(value.text.trim(), fit: BoxFit.contain),
                  ),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Choose image'),
                onPressed: () async {
                  try {
                    final image = await AdminFiles.pickImage();
                    if (mounted && image != null && _rows.contains(row)) {
                      row.controllers['img']!.text = image;
                    }
                  } catch (error) {
                    if (mounted) setState(() => _error = '$error');
                  }
                },
              ),
              TextButton(
                onPressed: () => row.controllers['img']!.clear(),
                child: const Text('Remove image'),
              ),
            ],
          ),
          AdminProductFields(
            controllers: row.controllers,
            categories: widget.categories,
            showAdvanced: false,
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(title: const Text('Bulk Products')),
      body: SafeArea(
        child: AbsorbPointer(
          absorbing: _saving,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Add multiple products',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Enter the details for each product, then save them together.',
                      ),
                      const SizedBox(height: 16),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      for (var index = 0; index < _rows.length; index++)
                        _row(_rows[index], index),
                      TextButton(
                        onPressed: () =>
                            setState(() => _rows.add(_ProductDraft())),
                        child: const Text('+ Add Product'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _saving || _rows.isEmpty ? null : _saveAll,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _saving
                    ? 'Saving products…'
                    : 'Save All Products (${_rows.length})',
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
