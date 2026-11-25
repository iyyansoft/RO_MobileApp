import 'cabinet_display_order.dart';
import 'category_price_view.dart';
import 'models/category_model.dart';
import 'models/product_model.dart';

String _norm(String value) => value.trim().toLowerCase().replaceAll('_', ' ');

/// The category shown when a product is shared.
///
/// 1. The page it is shared from ([view]): on the RO Systems page every
///    product listed there (its own products and the cross-listed Cabinet
///    products, see [categoryIncludes]) is shared as RO Systems; on the
///    Cabinet page a Cabinet product is shared as Cabinet. The name comes from
///    that category's record. The page applies only to products it lists.
/// 2. Otherwise the product's SAVED category (its category key/id), never its
///    name or SKU: the category whose id / database id it is, else the title
///    the server joined (`category_name`) unless that is only the raw key.
/// 3. Otherwise empty: the share then leaves the category out instead of
///    showing a wrong one.
String shareCategoryName(
  ProductModel product,
  Iterable<CategoryModel> categories, {
  ProductPriceView view = ProductPriceView.standard,
}) {
  final context = _pageCategory(product, categories, view);
  if (context != null) return context;
  final saved = _norm(product.categoryId);
  if (saved.isNotEmpty) {
    for (final c in categories) {
      if (_norm(c.id) == saved || _norm(c.databaseId ?? '') == saved) {
        final name = c.name.trim();
        if (name.isNotEmpty) return name;
      }
    }
  }
  final fromServer = product.categoryName.trim();
  if (fromServer.isEmpty || _norm(fromServer) == saved) return '';
  return fromServer;
}

/// The category of the page [view] stands for, if that page lists [product].
String? _pageCategory(
  ProductModel product,
  Iterable<CategoryModel> categories,
  ProductPriceView view,
) {
  final bool Function(CategoryModel) isPage = switch (view) {
    ProductPriceView.roSystems => isRoSystemsCategory,
    ProductPriceView.cabinet => isCabinetCategory,
    ProductPriceView.standard => (_) => false,
  };
  for (final page in categories.where(isPage)) {
    if (categoryIncludes(page, product, categories)) {
      final name = page.name.trim();
      if (name.isNotEmpty) return name;
    }
  }
  return null;
}

/// [product] with [shareCategoryName] as its category, used by every share
/// path (share text, WhatsApp/native share and the share card image).
ProductModel productForSharing(
  ProductModel product,
  Iterable<CategoryModel> categories, {
  ProductPriceView view = ProductPriceView.standard,
}) {
  final name = shareCategoryName(product, categories, view: view);
  return name == product.categoryName ? product : product.withCategoryName(name);
}
