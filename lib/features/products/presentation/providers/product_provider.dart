import '../../../../core/network/api_client.dart';
import '../../../../core/supabase/supabase_config.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/product_model.dart';
import '../../domain/models/category_model.dart';
import '../../domain/cabinet_display_order.dart';
import '../../domain/category_price_view.dart';

enum SortOption {
  popularity('Popularity'),
  priceLowToHigh('Price: Low to High'),
  priceHighToLow('Price: High to Low'),
  discountHighToLow('Discount: High to Low'),
  newest('Newest First');

  final String label;
  const SortOption(this.label);
}

class ProductFilterState {
  final String searchQuery;
  final String? selectedCategoryId;
  final SortOption sortOption;
  final double minPrice;
  final double maxPrice;
  final bool inStockOnly;
  final Set<String> selectedBrands;
  final bool isGridView;
  final bool isLoading;
  final bool isLoadingMore;
  final int page;
  final bool hasMore;

  const ProductFilterState({
    this.searchQuery = '',
    this.selectedCategoryId,
    this.sortOption = SortOption.popularity,
    this.minPrice = 0.0,
    this.maxPrice = 30000.0,
    this.inStockOnly = false,
    this.selectedBrands = const {},
    // Start with the product image beside its details; the listing toolbar
    // still lets users switch to the existing grid layout.
    this.isGridView = true,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.page = 1,
    this.hasMore = false,
  });

  ProductFilterState copyWith({
    String? searchQuery,
    String? selectedCategoryId,
    bool clearCategory = false,
    SortOption? sortOption,
    double? minPrice,
    double? maxPrice,
    bool? inStockOnly,
    Set<String>? selectedBrands,
    bool? isGridView,
    bool? isLoading,
    bool? isLoadingMore,
    int? page,
    bool? hasMore,
  }) {
    return ProductFilterState(
      searchQuery: searchQuery ?? this.searchQuery,
      selectedCategoryId: clearCategory
          ? null
          : (selectedCategoryId ?? this.selectedCategoryId),
      sortOption: sortOption ?? this.sortOption,
      minPrice: minPrice ?? this.minPrice,
      maxPrice: maxPrice ?? this.maxPrice,
      inStockOnly: inStockOnly ?? this.inStockOnly,
      selectedBrands: selectedBrands ?? this.selectedBrands,
      isGridView: isGridView ?? this.isGridView,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}

class ProductNotifier extends StateNotifier<ProductFilterState> {
  ProductNotifier({ProductFilterState? initialState})
    : super(initialState ?? const ProductFilterState());

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query, page: 1, hasMore: true);
  }

  void selectCategory(String? categoryId) {
    if (categoryId == null) {
      state = state.copyWith(clearCategory: true, page: 1, hasMore: true);
    } else {
      state = state.copyWith(
        selectedCategoryId: categoryId,
        page: 1,
        hasMore: true,
      );
    }
  }

  void setSortOption(SortOption option) {
    state = state.copyWith(sortOption: option);
  }

  void setPriceRange(double min, double max) {
    state = state.copyWith(minPrice: min, maxPrice: max, page: 1);
  }

  void toggleInStockOnly(bool value) {
    state = state.copyWith(inStockOnly: value, page: 1);
  }

  void toggleBrand(String brand) {
    final current = Set<String>.from(state.selectedBrands);
    if (current.contains(brand)) {
      current.remove(brand);
    } else {
      current.add(brand);
    }
    state = state.copyWith(selectedBrands: current, page: 1);
  }

  void clearFilters() {
    state = state.copyWith(
      clearCategory: true,
      minPrice: 0.0,
      maxPrice: 30000.0,
      inStockOnly: false,
      selectedBrands: {},
      page: 1,
    );
  }

  void toggleViewMode() {
    state = state.copyWith(isGridView: !state.isGridView);
  }

  Future<void> loadMoreProducts() async {
    if (state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);

    state = state.copyWith(isLoadingMore: false, hasMore: false);
  }
}

final productFilterProvider =
    StateNotifierProvider<ProductNotifier, ProductFilterState>((ref) {
      return ProductNotifier();
    });

/// Injectable so the catalog providers can be exercised against an isolated
/// Supabase instance without changing the app's configured client.
final supabaseCatalogClientProvider = Provider<SupabaseClient>(
  (ref) => SupabaseConfig.client,
);

/// Reads the dealer catalog from its configured source (Express `/api/products`
/// by default, or the Supabase `catalog_products` view when enabled). Shared by
/// [catalogProductsProvider] and the background refresh in
/// `CatalogAutoRefresh`, so both always read the same backend and database.
final catalogProductsLoaderProvider =
    Provider<Future<List<ProductModel>> Function()>((ref) {
      if (SupabaseConfig.catalogEnabled) {
        final client = ref.watch(supabaseCatalogClientProvider);
        return () => _loadSupabaseProducts(client);
      }
      final api = ref.watch(apiClientProvider);
      return () async {
        final response = await api.get('products');
        return ((response.data as Map)['products'] as List)
            .map(
              (e) => ProductModel.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList();
      };
    });

final catalogCategoriesLoaderProvider =
    Provider<Future<List<CategoryModel>> Function()>((ref) {
      if (SupabaseConfig.catalogEnabled) {
        final client = ref.watch(supabaseCatalogClientProvider);
        return () => _loadSupabaseCategories(client);
      }
      final api = ref.watch(apiClientProvider);
      return () async {
        final response = await api.get('categories');
        return ((response.data as Map)['categories'] as List)
            .map(
              (e) =>
                  CategoryModel.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList();
      };
    });

/// Holds a catalog that the background refresh has already downloaded, so
/// re-running the catalog providers uses it instead of fetching again.
class CatalogHandOff {
  List<ProductModel>? products;
  List<CategoryModel>? categories;

  List<ProductModel>? takeProducts() {
    final value = products;
    products = null;
    return value;
  }

  List<CategoryModel>? takeCategories() {
    final value = categories;
    categories = null;
    return value;
  }
}

final catalogHandOffProvider = Provider<CatalogHandOff>(
  (ref) => CatalogHandOff(),
);

/// Fields the customer app shows; a change in any of them means the catalog
/// on screen is out of date.
String productCatalogSignature(List<ProductModel> products) => [
  for (final p in products)
    [
      p.id,
      p.name,
      p.sku,
      p.categoryId,
      p.categoryName,
      p.brand,
      p.dealerPrice,
      p.mrp,
      p.cabinetPrice,
      p.imageUrl,
      p.stockStatus.name,
      p.moq,
      p.moqSet,
      p.moqUnit,
      p.stockQuantity,
      p.rating,
      p.isFeatured,
      p.description,
      p.createdAt?.toIso8601String(),
      p.specifications,
      p.features,
    ].join('\u0001'),
].join('\u0002');

String categoryCatalogSignature(List<CategoryModel> categories) => [
  for (final c in categories)
    [c.id, c.databaseId, c.name, c.imagePath, c.description].join('\u0001'),
].join('\u0002');

final catalogProductsProvider = FutureProvider<List<ProductModel>>((ref) async {
  final load = ref.watch(catalogProductsLoaderProvider);
  final handedOff = ref.read(catalogHandOffProvider).takeProducts();
  if (handedOff != null) return handedOff;
  return load();
});

Future<List<ProductModel>> _loadSupabaseProducts(SupabaseClient client) async {
  final rows = await client
      .from('catalog_products')
      // Keep the mobile contract explicit: the public catalog surface must
      // never fetch internal purchase pricing or future privileged fields.
      .select(
        'id,category_id,category_key,category_name,sku,name,brand,price,'
        'dealer_price,mrp,moq,badge,rating,img,description,desc,specs,'
        'features,applications,stock_quantity,status,created_at',
      )
      .order('category_key', ascending: true)
      .order('name', ascending: true);
  return rows
      .map((row) => ProductModel.fromJson(Map<String, dynamic>.from(row)))
      .toList();
}

Future<List<CategoryModel>> _loadSupabaseCategories(
  SupabaseClient client,
) async {
  final rows = await client
      .from('categories')
      .select(
        'id,key_name,title,description,badge_text,icon_color,image_url,'
        'display_order',
      )
      .order('display_order', ascending: true);
  return rows
      .map((row) => CategoryModel.fromJson(Map<String, dynamic>.from(row)))
      .toList();
}

final catalogCategoriesProvider = FutureProvider<List<CategoryModel>>((
  ref,
) async {
  final load = ref.watch(catalogCategoriesLoaderProvider);
  final handedOff = ref.read(catalogHandOffProvider).takeCategories();
  if (handedOff != null) return handedOff;
  return load();
});
final categoriesProvider = Provider<List<CategoryModel>>((ref) {
  final categories = ref.watch(catalogCategoriesProvider).valueOrNull ?? [];
  final products = ref.watch(allProductsProvider);
  return categories
      .map(
        (category) => category.withProductCount(
          products
              .where((p) => categoryIncludes(category, p, categories))
              .length,
        ),
      )
      .toList();
});
final allProductsProvider = Provider<List<ProductModel>>(
  (ref) => ref.watch(catalogProductsProvider).valueOrNull ?? [],
);

final filteredProductsProvider = Provider<List<ProductModel>>((ref) {
  return listingProducts(
    ref.watch(allProductsProvider),
    ref.watch(categoriesProvider),
    ref.watch(productFilterProvider),
  );
}, dependencies: [productFilterProvider]);

/// The products a listing page shows for [filterState]: search, category,
/// price, stock and brand filters, then the sort. Shared by the listing
/// pages and the Home Best Sellers slider (which shows the RO Systems
/// category exactly as its category page does).
List<ProductModel> listingProducts(
  List<ProductModel> allProducts,
  List<CategoryModel> categories,
  ProductFilterState filterState,
) {
  final selectedCategories = categories.where(
    (category) =>
        category.id == filterState.selectedCategoryId ||
        category.databaseId == filterState.selectedCategoryId,
  );
  final selectedCategory = selectedCategories.isEmpty
      ? null
      : selectedCategories.first;
  // Price filter and price sort use the price the page shows (Cabinet Price
  // on the Cabinets page, Dealer Price elsewhere).
  final view = priceViewFor(selectedCategory);
  final price = view.listedPrice;

  List<ProductModel> filtered = allProducts.where((product) {
    // 1. Search Query
    if (filterState.searchQuery.isNotEmpty) {
      final q = filterState.searchQuery.toLowerCase();
      final matchesName = product.name.toLowerCase().contains(q);
      final matchesSku = product.sku.toLowerCase().contains(q);
      final matchesBrand = product.brand.toLowerCase().contains(q);
      final matchesCategory = product.categoryName.toLowerCase().contains(q);
      if (!matchesName && !matchesSku && !matchesBrand && !matchesCategory) {
        return false;
      }
    }

    // 2. Category Filter
    if (filterState.selectedCategoryId != null) {
      // RO Systems also lists the Cabinet products (same records).
      if (!(selectedCategory != null
          ? categoryIncludes(selectedCategory, product, categories)
          : product.categoryId == filterState.selectedCategoryId)) {
        return false;
      }
    }

    // 3. Price Filter
    if (price(product) < filterState.minPrice ||
        (filterState.maxPrice < 30000 &&
            price(product) > filterState.maxPrice)) {
      return false;
    }

    // 4. In Stock Filter
    if (filterState.inStockOnly &&
        product.stockStatus == StockStatus.outOfStock) {
      return false;
    }

    // 5. Brand Filter
    if (filterState.selectedBrands.isNotEmpty) {
      if (!filterState.selectedBrands.contains(product.brand)) {
        return false;
      }
    }

    return true;
  }).toList();

  // Sort (stable: equal products keep the catalogue order, the same on
  // every platform and after every refresh).
  switch (filterState.sortOption) {
    case SortOption.priceLowToHigh:
      _stableSort(filtered, (a, b) => price(a).compareTo(price(b)));
      break;
    case SortOption.priceHighToLow:
      _stableSort(filtered, (a, b) => price(b).compareTo(price(a)));
      break;
    case SortOption.discountHighToLow:
      _stableSort(
        filtered,
        (a, b) => b.discountPercentage.compareTo(a.discountPercentage),
      );
      break;
    case SortOption.popularity:
      _stableSort(filtered, (a, b) => b.rating.compareTo(a.rating));
      break;
    case SortOption.newest:
      filtered = ProductModel.newestFirst(filtered);
      break;
  }

  // Cabinet category, default order: the six 20" housings go last. A sort
  // the dealer picks (price, discount, newest) is left as chosen.
  if (filterState.sortOption == SortOption.popularity &&
      (isCabinetCategory(selectedCategory) ||
          isRoSystemsCategory(selectedCategory))) {
    filtered = cabinetDisplayOrder(filtered);
  }

  return filtered;
}

/// Sorts [list] in place by [compare]; products that compare equal keep their
/// existing (catalogue) order. `List.sort` alone may reorder them on lists
/// longer than 32, differently on the web and on Android.
void _stableSort(
  List<ProductModel> list,
  int Function(ProductModel a, ProductModel b) compare,
) {
  final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
  indexed.sort((a, b) {
    final byValue = compare(a.$2, b.$2);
    return byValue != 0 ? byValue : a.$1.compareTo(b.$1);
  });
  for (var i = 0; i < indexed.length; i++) {
    list[i] = indexed[i].$2;
  }
}

/// Home Best Sellers: exactly the RO Systems category page's list in its
/// default order (Popularity), the same [listingProducts] call that page
/// makes: its own products and the cross-listed Cabinet products, nothing
/// selected separately. Recomputed from the latest catalogue; empty when
/// there is no RO Systems category.
final roSystemsBestSellersProvider = Provider<List<ProductModel>>((ref) {
  final categories = ref.watch(categoriesProvider);
  final roSystems = categories.where(isRoSystemsCategory);
  if (roSystems.isEmpty) return const [];
  return listingProducts(
    ref.watch(allProductsProvider),
    categories,
    ProductFilterState(selectedCategoryId: roSystems.first.id),
  );
});
