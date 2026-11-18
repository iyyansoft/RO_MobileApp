import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/cabinet_display_order.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/category_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/providers/product_provider.dart';

ProductModel p(
  String sku,
  String name,
  String category, {
  double price = 100,
}) => ProductModel.fromJson({
  'id': 'id-$sku',
  'sku': sku,
  'name': name,
  'category': category,
  'price': price,
  'mrp': 0,
  'rating': 0,
});

// Catalogue order from the API (category, then name): the 20" housings
// (CAB-36..41) sort first by name.
final catalog = [
  p('CAB-39', '20"Slim housing-RP', 'cabinets', price: 280),
  p('CAB-41', '20"Slim housing-White/blue', 'cabinets', price: 430),
  p('CAB-40', '20"Slim housing-b/v tup RD', 'cabinets', price: 360),
  p('CAB-38', '20"eco verjin white/blue-', 'cabinets', price: 950),
  p('CAB-37', '20"jambo housing eco v/rp 102', 'cabinets', price: 850),
  p('CAB-36', '20"jambo housing-eco jambo204', 'cabinets', price: 750),
  p('CAB-15', 'Aqua 2090 -premium gray602', 'cabinets', price: 4650),
  p('CAB-18', 'Aqua 2090 raga series cabinets', 'cabinets', price: 5300),
  p('CAB-01', 'Dolphin king/ABS', 'cabinets', price: 3700),
  p('CAB-35', 'Water lilly', 'cabinets', price: 4500),
  p('RO-FLT-1', '20" filter (not a cabinet)', 'filters', price: 50),
  p('RO-FLT-2', 'Alpha filter', 'filters', price: 60),
];

const categories = [
  CategoryModel(
    id: 'filters',
    name: 'Filters',
    imagePath: '',
    productCount: 0,
    description: '',
  ),
  CategoryModel(
    id: 'cabinets',
    name: 'Cabinet',
    imagePath: '',
    productCount: 0,
    description: '',
    databaseId: 'CAT_CAB',
  ),
];

List<String> skus(List<ProductModel> list) => [for (final x in list) x.sku];

List<ProductModel> listing({
  String? category,
  String query = '',
  SortOption? sort,
  double? maxPrice,
}) {
  final c = ProviderContainer(
    overrides: [
      allProductsProvider.overrideWithValue(catalog),
      categoriesProvider.overrideWithValue(categories),
    ],
  );
  addTearDown(c.dispose);
  final n = c.read(productFilterProvider.notifier);
  n.selectCategory(category);
  if (query.isNotEmpty) n.setSearchQuery(query);
  if (sort != null) n.setSortOption(sort);
  if (maxPrice != null) n.setPriceRange(0, maxPrice);
  return c.read(filteredProductsProvider);
}

void main() {
  test('the six shown last are exactly CAB-36..CAB-41', () {
    expect(cabinetShownLastSkus, {
      'CAB-36',
      'CAB-37',
      'CAB-38',
      'CAB-39',
      'CAB-40',
      'CAB-41',
    });
  });

  test('Cabinet category: existing products first, the six at the end, each group in its order', () {
    final shown = listing(category: 'cabinets');
    expect(skus(shown), [
      'CAB-15',
      'CAB-18',
      'CAB-01',
      'CAB-35',
      'CAB-39',
      'CAB-41',
      'CAB-40',
      'CAB-38',
      'CAB-37',
      'CAB-36',
    ]);
    // Same products, none lost or duplicated, data untouched.
    expect(shown.toSet().length, 10);
    expect(shown.firstWhere((x) => x.sku == 'CAB-40').dealerPrice, 360);
    // Selected by database id too.
    expect(skus(listing(category: 'CAT_CAB')), skus(shown));
  });

  test('other categories and the all-products list keep their order', () {
    expect(skus(listing(category: 'filters')), ['RO-FLT-1', 'RO-FLT-2']);
    final all = listing();
    expect(all.length, catalog.length);
    expect(all.first.sku, 'CAB-39', reason: 'no category selected: unchanged');
  });

  test('search, price filter and chosen sorts still work in Cabinet', () {
    expect(skus(listing(category: 'cabinets', query: 'housing')), [
      'CAB-39',
      'CAB-41',
      'CAB-40',
      'CAB-37',
      'CAB-36',
    ]);
    expect(skus(listing(category: 'cabinets', query: 'aqua')), [
      'CAB-15',
      'CAB-18',
    ]);
    expect(skus(listing(category: 'cabinets', maxPrice: 1000)), [
      'CAB-39',
      'CAB-41',
      'CAB-40',
      'CAB-38',
      'CAB-37',
      'CAB-36',
    ]);
    expect(
      skus(listing(category: 'cabinets', sort: SortOption.priceLowToHigh))
          .first,
      'CAB-39',
    );
    expect(
      skus(listing(category: 'cabinets', sort: SortOption.priceHighToLow))
          .first,
      'CAB-18',
    );
  });

  test('isCabinetCategory', () {
    expect(isCabinetCategory(categories[1]), isTrue);
    expect(isCabinetCategory(categories[0]), isFalse);
    expect(isCabinetCategory(null), isFalse);
  });
}
