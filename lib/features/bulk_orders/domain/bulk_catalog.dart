import '../../products/domain/models/category_model.dart';
import '../../products/domain/models/product_model.dart';

/// Categories offered in Bulk Orders, in display order (by category key /
/// database id). RO Systems, Cabinet and Booster Pumps are not offered.
const bulkCategoryKeys = ['membranes', 'filters', 'pipes', 'spares'];
const _bulkCategoryIds = {
  'membranes': 'cat_mem',
  'filters': 'cat_flt',
  'pipes': 'cat_pip',
  'spares': 'cat_spr',
};

/// The Bulk Orders key of [category], or null when it is not offered.
String? bulkCategoryKey(CategoryModel category) {
  final id = category.id.trim().toLowerCase();
  final dbId = (category.databaseId ?? '').trim().toLowerCase();
  for (final key in bulkCategoryKeys) {
    if (id == key || dbId == _bulkCategoryIds[key] || dbId == key) return key;
  }
  return null;
}

/// The Bulk Orders categories present in [categories], in display order.
List<CategoryModel> bulkCategories(List<CategoryModel> categories) => [
  for (final key in bulkCategoryKeys)
    ...categories.where((c) => bulkCategoryKey(c) == key).take(1),
];

/// Products of [category] that have a bulk offer (same product records as
/// the normal catalogue).
List<ProductModel> bulkProductsIn(
  CategoryModel category,
  List<ProductModel> products,
) =>
    products.where((p) => p.hasBulkOffer && category.matchesProduct(p)).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

/// "Minimum Pack" when the step is a whole pack (Domestic PDF), else
/// "Minimum Order Qty" (Mukhil PDF: Mini qty, then +1).
String bulkMinimumLabel(ProductModel product) =>
    (product.bulkStep ?? 1) > 1 ? 'Minimum Pack' : 'Minimum Order Qty';

/// How the quantity steps up: "+60 (1 pack)" or "+1 piece".
String bulkIncrementLabel(ProductModel product) {
  final step = product.bulkStep ?? 1;
  return step > 1 ? '+$step (1 pack)' : '+1 piece';
}
