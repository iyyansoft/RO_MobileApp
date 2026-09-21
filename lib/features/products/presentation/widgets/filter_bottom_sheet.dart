import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../providers/product_provider.dart';

class FilterBottomSheet extends ConsumerStatefulWidget {
  const FilterBottomSheet({super.key});

  @override
  ConsumerState<FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends ConsumerState<FilterBottomSheet> {
  late RangeValues _priceRange;
  late bool _inStockOnly;
  late Set<String> _selectedBrands;

  final List<String> _availableBrands = [
    'AquaClean',
    'Vontron',
    'E-Chen',
    'Kemflo',
    'Hero',
    'HydroShield',
    'PowerAmp',
    'AquaTech',
  ];

  @override
  void initState() {
    super.initState();
    final filter = ref.read(productFilterProvider);
    _priceRange = RangeValues(filter.minPrice, filter.maxPrice);
    _inStockOnly = filter.inStockOnly;
    _selectedBrands = Set<String>.from(filter.selectedBrands);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? AppColors.accentDark : AppColors.primaryLight;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Title & Reset
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Filter Products',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    ref.read(productFilterProvider.notifier).clearFilters();
                    Navigator.pop(context);
                  },
                  child: const Text('Reset All', style: TextStyle(color: Colors.redAccent)),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 12),

            // 1. Price Range Filter
            Text(
              'Dealer Price Range',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('₹${_priceRange.start.round()}'),
                Text('₹${_priceRange.end.round()}'),
              ],
            ),
            RangeSlider(
              values: _priceRange,
              min: 0,
              max: 30000,
              divisions: 60,
              activeColor: primaryColor,
              labels: RangeLabels(
                '₹${_priceRange.start.round()}',
                '₹${_priceRange.end.round()}',
              ),
              onChanged: (RangeValues values) {
                setState(() {
                  _priceRange = values;
                });
              },
            ),
            const SizedBox(height: 16),

            // 2. Stock Filter
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.04) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.inventory_2_outlined, color: primaryColor, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        'In Stock Items Only',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  Switch.adaptive(
                    value: _inStockOnly,
                    activeColor: primaryColor,
                    onChanged: (val) {
                      setState(() {
                        _inStockOnly = val;
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 3. Brand Filter
            Text(
              'Filter by Brand',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _availableBrands.map((brand) {
                final isSelected = _selectedBrands.contains(brand);
                return FilterChip(
                  label: Text(brand),
                  selected: isSelected,
                  selectedColor: primaryColor.withOpacity(0.18),
                  checkmarkColor: primaryColor,
                  labelStyle: TextStyle(
                    color: isSelected
                        ? primaryColor
                        : (isDark ? Colors.white70 : Colors.black87),
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                    fontSize: 11.5,
                  ),
                  onSelected: (bool selected) {
                    setState(() {
                      if (selected) {
                        _selectedBrands.add(brand);
                      } else {
                        _selectedBrands.remove(brand);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // Apply Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  ref
                      .read(productFilterProvider.notifier)
                      .setPriceRange(_priceRange.start, _priceRange.end);
                  ref
                      .read(productFilterProvider.notifier)
                      .toggleInStockOnly(_inStockOnly);

                  // Update selected brands
                  final notifier = ref.read(productFilterProvider.notifier);
                  final current = ref.read(productFilterProvider).selectedBrands;
                  for (final b in _availableBrands) {
                    if (_selectedBrands.contains(b) && !current.contains(b)) {
                      notifier.toggleBrand(b);
                    } else if (!_selectedBrands.contains(b) && current.contains(b)) {
                      notifier.toggleBrand(b);
                    }
                  }

                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 4,
                ),
                child: const Text(
                  'Apply Filters',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
