import 'models/category_model.dart';
import 'models/product_model.dart';

/// Cabinet products shown at the end of the Cabinet category.
///
/// These are the last six rows of the supplier PDF (the 20" housings). All 41
/// Cabinet products share one import timestamp, so they are identified by SKU
/// (an explicit display priority). Display order only: no product data is
/// changed.
const cabinetShownLastSkus = {
  'CAB-36',
  'CAB-37',
  'CAB-38',
  'CAB-39',
  'CAB-40',
  'CAB-41',
};

/// True for the Cabinet category (id/key "cabinets" or "CAT_CAB", or named
/// "Cabinet"/"Cabinets").
bool isCabinetCategory(CategoryModel? category) {
  if (category == null) return false;
  final names = [
    category.id,
    category.databaseId ?? '',
    category.name,
  ].map((v) => v.trim().toLowerCase());
  return names.any((v) => v == 'cabinets' || v == 'cabinet' || v == 'cat_cab');
}

/// [products] with the [cabinetShownLastSkus] products moved to the end.
/// Both groups keep their existing order; nothing is added or removed.
List<ProductModel> cabinetDisplayOrder(Iterable<ProductModel> products) {
  bool last(ProductModel p) =>
      cabinetShownLastSkus.contains(p.sku.trim().toUpperCase());
  return [
    for (final p in products)
      if (!last(p)) p,
    for (final p in products)
      if (last(p)) p,
  ];
}
