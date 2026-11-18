import '../../products/domain/models/product_model.dart';

/// Cabinet cards visible at once in the Best Sellers slider on wide screens
/// (narrower screens show fewer so the cards stay readable); the rest are
/// reached by scrolling sideways. The products themselves come from
/// `cabinetCategoryProductsProvider` (the Cabinet category page's list).
const homeBestSellerVisibleDesktop = 4;
const homeBestSellerVisibleTablet = 3;
const homeBestSellerVisiblePhone = 2;

/// Best Sellers when the catalogue has no Cabinet category (e.g. before the
/// Cabinet import): products 30% or more below MRP, or the whole catalogue
/// if none are (the previous rule).
List<ProductModel> homeBestSellersFallback(List<ProductModel> all) {
  final discounted = all.where((p) => p.discountPercentage >= 30).toList();
  return discounted.isEmpty ? all : discounted;
}
