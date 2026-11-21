import 'cabinet_display_order.dart';
import 'models/category_model.dart';
import 'models/product_model.dart';

/// How a product's price is shown, from the category page it is viewed on.
/// Display only: cart, checkout, orders and invoices always use the product's
/// Dealer Price, and no stored price is changed.
enum ProductPriceView {
  /// Existing display (Dealer Price, MRP, discount, Cabinet Price line).
  standard,

  /// Cabinets category: the Cabinet Price only (no Dealer Price or MRP).
  cabinet,

  /// RO Systems category: Dealer Price + struck-through MRP + discount;
  /// never the Cabinet Price.
  roSystems;

  /// Query value used in `/products/:id?view=...` links.
  String get query => switch (this) {
    ProductPriceView.cabinet => 'cabinet',
    ProductPriceView.roSystems => 'ro-systems',
    ProductPriceView.standard => '',
  };

  static ProductPriceView fromQuery(String? value) => switch (value) {
    'cabinet' => ProductPriceView.cabinet,
    'ro-systems' => ProductPriceView.roSystems,
    _ => ProductPriceView.standard,
  };

  /// Whether [product] is shown with its Cabinet Price as the only price
  /// (Cabinets view, and the product has one; otherwise the standard
  /// display is kept rather than showing no price).
  bool cabinetOnly(ProductModel product) =>
      this == ProductPriceView.cabinet && product.hasCabinetPrice;

  /// Whether the "Cabinet Price: ..." line may be shown under the price.
  bool showsCabinetLine(ProductModel product) =>
      this == ProductPriceView.standard && product.hasCabinetPrice;

  /// The price the listing sorts and filters by: what the customer sees.
  double listedPrice(ProductModel product) =>
      cabinetOnly(product) ? product.cabinetPrice! : product.dealerPrice;
}

/// True for the RO Systems category (key "systems", id "CAT_SYS", or named
/// "RO Systems").
bool isRoSystemsCategory(CategoryModel? category) {
  if (category == null) return false;
  final names = [
    category.id,
    category.databaseId ?? '',
    category.name,
  ].map((v) => v.trim().toLowerCase());
  return names.any(
    (v) => v == 'systems' || v == 'cat_sys' || v == 'ro systems',
  );
}

/// Price display for a category page.
ProductPriceView priceViewFor(CategoryModel? category) {
  if (isCabinetCategory(category)) return ProductPriceView.cabinet;
  if (isRoSystemsCategory(category)) return ProductPriceView.roSystems;
  return ProductPriceView.standard;
}

/// Whether [category]'s page lists [product]: its own products, and for RO
/// Systems also every product of the Cabinet category (the same product
/// records; nothing is duplicated).
bool categoryIncludes(
  CategoryModel category,
  ProductModel product,
  Iterable<CategoryModel> allCategories,
) {
  if (category.matchesProduct(product)) return true;
  if (!isRoSystemsCategory(category)) return false;
  return allCategories.any(
    (c) => isCabinetCategory(c) && c.matchesProduct(product),
  );
}
