import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../products/domain/models/category_model.dart';

class AdminProductFields extends StatelessWidget {
  final Map<String, TextEditingController> controllers;
  final List<CategoryModel> categories;
  final bool showAdvanced;
  const AdminProductFields({
    super.key,
    required this.controllers,
    this.categories = const [],
    this.showAdvanced = true,
  });

  /// Money fields that may be left empty (sent as '' = not set).
  static const optionalAmounts = ['purchase_price', 'price', 'mrp'];

  /// The Cabinet category: id/key "CAT_CAB" or "cabinets", or titled "Cabinet".
  static bool isCabinetCategory(String? value, List<CategoryModel> categories) {
    final v = (value ?? '').trim().toLowerCase();
    if (v.isEmpty) return false;
    if (v == 'cabinets' || v == 'cat_cab') return true;
    return categories.any(
      (c) =>
          c.id.toLowerCase() == v &&
          ['cabinet', 'cabinets'].contains(c.name.trim().toLowerCase()),
    );
  }

  /// "Cabinet Price (₹) *": shown and required only for the Cabinet category.
  Widget _cabinetPrice() {
    final category = controllers['category'];
    final input = controllers['cabinet_price'];
    if (category == null || input == null) return const SizedBox.shrink();
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: category,
      builder: (_, value, __) {
        if (!isCabinetCategory(value.text, categories)) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextFormField(
            key: const ValueKey('cabinet_price'),
            controller: input,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Cabinet Price (₹) *',
              prefixText: '₹ ',
            ),
            validator: (value) {
              final amount = num.tryParse((value ?? '').trim());
              if ((value ?? '').trim().isEmpty) return 'Required';
              if (amount == null || !amount.isFinite || amount <= 0) {
                return 'Cabinet Price must be greater than zero';
              }
              return null;
            },
          ),
        );
      },
    );
  }

  static const labels = {
    'name': 'Name',
    'sku': 'SKU',
    'category': 'Category',
    'brand': 'Brand',
    'purchase_price': 'Purchase Price',
    'price': 'Dealer Price',
    'mrp': 'MRP',
    'moq': 'MOQ',
    'stock_quantity': 'Stock',
    'desc': 'Description',
    'img': 'Image URL',
    'min_stock': 'Low stock threshold',
    'rating': 'Rating',
    'specs': 'Specifications (JSON)',
    'features': 'Features (JSON)',
    'badge': 'Product badge',
    'status': 'Status',
  };

  Widget _field(String key) {
    final numeric = [
      'purchase_price',
      'price',
      'mrp',
      'stock_quantity',
      'min_stock',
      'rating',
    ].contains(key);
    if (key == 'category' && categories.isNotEmpty) {
      final options = {
        for (final category in categories) category.id: category.name,
      };
      final selected = controllers[key]!.text.trim();
      if (selected.isNotEmpty) options.putIfAbsent(selected, () => selected);
      return DropdownButtonFormField<String>(
        initialValue: selected.isEmpty ? null : selected,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Category'),
        items: options.entries
            .map(
              (entry) => DropdownMenuItem(
                value: entry.key,
                child: Text(entry.value, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: (value) {
          controllers[key]!.text = value ?? '';
          // Leaving Cabinet hides and clears Cabinet Price.
          if (!isCabinetCategory(value, categories)) {
            controllers['cabinet_price']?.clear();
          }
        },
        validator: (value) =>
            value == null || value.isEmpty ? 'Choose a category' : null,
      );
    }
    if (key == 'status') {
      return DropdownButtonFormField<String>(
        initialValue: controllers[key]!.text,
        decoration: const InputDecoration(labelText: 'Status'),
        items: const [
          DropdownMenuItem(value: 'active', child: Text('Active')),
          DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
        ],
        onChanged: (value) => controllers[key]!.text = value ?? 'active',
      );
    }
    return TextFormField(
      controller: controllers[key],
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : null,
      maxLines: ['desc', 'specs', 'features'].contains(key) ? 3 : 1,
      decoration: InputDecoration(
        labelText: labels[key],
        prefixText: ['purchase_price', 'price', 'mrp'].contains(key)
            ? '₹ '
            : null,
      ),
      validator: (value) {
        final text = (value ?? '').trim();
        if (['name', 'sku', 'category'].contains(key) && text.isEmpty) {
          return 'Required';
        }
        // Brand, Purchase Price, Dealer Price and MRP are optional.
        if (optionalAmounts.contains(key) && text.isEmpty) return null;
        if (numeric) {
          final amount = num.tryParse(text);
          if (amount == null || !amount.isFinite || amount < 0) {
            return 'Enter a nonnegative number';
          }
          if (key == 'price' && amount <= 0) {
            return 'Dealer Price must be greater than zero';
          }
          if (key == 'mrp' && amount <= 0) {
            return 'MRP must be greater than zero';
          }
          if (['stock_quantity', 'min_stock'].contains(key) &&
              amount != amount.round()) {
            return 'Enter a whole number';
          }
        }
        // Blank MOQ is allowed: it means "not set" and is kept blank.
        if (key == 'moq' && text.isNotEmpty) {
          final amount = int.tryParse(
            RegExp(r'\d+').firstMatch(text)?.group(0) ?? '',
          );
          if (amount == null || amount < 1 || text.startsWith('-')) {
            return 'MOQ must be at least 1';
          }
        }
        if (['specs', 'features'].contains(key)) {
          try {
            final decoded = jsonDecode(text);
            if (key == 'specs' ? decoded is! Map : decoded is! List) {
              return 'Invalid JSON type';
            }
          } catch (_) {
            return 'Enter valid JSON';
          }
        }
        return null;
      },
    );
  }

  Widget _group(String title, List<String> keys) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ),
      LayoutBuilder(
        builder: (context, constraints) => Wrap(
          spacing: 12,
          runSpacing: 16,
          children: [
            for (final key in keys)
              SizedBox(
                width: constraints.maxWidth >= 460 && key != 'desc'
                    ? (constraints.maxWidth - 12) / 2
                    : constraints.maxWidth,
                child: _field(key),
              ),
          ],
        ),
      ),
      const SizedBox(height: 8),
    ],
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _group('Product information', [
        'img',
        'name',
        'sku',
        'category',
        'brand',
      ]),
      _cabinetPrice(),
      _group('Pricing', ['purchase_price', 'price', 'mrp']),
      _group('Inventory', ['moq', 'stock_quantity']),
      _group('Description', ['desc']),
      if (showAdvanced)
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Advanced settings'),
          children: [
            _group('Additional details', [
              'min_stock',
              'rating',
              'specs',
              'features',
              'badge',
              'status',
            ]),
          ],
        ),
    ],
  );
}
