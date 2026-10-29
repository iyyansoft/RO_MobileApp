import '../../../../core/network/api_client.dart';
import '../../../../core/supabase/supabase_config.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/product_model.dart';
import '../../domain/models/category_model.dart';

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
    this.isGridView = false,
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

final catalogProductsProvider = FutureProvider<List<ProductModel>>((ref) async {
  if (SupabaseConfig.catalogEnabled) {
    final rows = await ref
        .watch(supabaseCatalogClientProvider)
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
  final response = await ref.watch(apiClientProvider).get('products');
  return ((response.data as Map)['products'] as List)
      .map((e) => ProductModel.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList();
});
final catalogCategoriesProvider = FutureProvider<List<CategoryModel>>((
  ref,
) async {
  if (SupabaseConfig.catalogEnabled) {
    final rows = await ref
        .watch(supabaseCatalogClientProvider)
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
  final response = await ref.watch(apiClientProvider).get('categories');
  return ((response.data as Map)['categories'] as List)
      .map((e) => CategoryModel.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList();
});
final categoriesProvider = Provider<List<CategoryModel>>((ref) {
  final categories = ref.watch(catalogCategoriesProvider).valueOrNull ?? [];
  final products = ref.watch(allProductsProvider);
  return categories
      .map(
        (category) => category.withProductCount(
          products.where(category.matchesProduct).length,
        ),
      )
      .toList();
});
final allProductsProvider = Provider<List<ProductModel>>(
  (ref) => ref.watch(catalogProductsProvider).valueOrNull ?? [],
);

final filteredProductsProvider = Provider<List<ProductModel>>((ref) {
  final filterState = ref.watch(productFilterProvider);
  final allProducts = ref.watch(allProductsProvider);
  final categories = ref.watch(categoriesProvider);
  final selectedCategories = categories.where(
    (category) =>
        category.id == filterState.selectedCategoryId ||
        category.databaseId == filterState.selectedCategoryId,
  );
  final selectedCategory = selectedCategories.isEmpty
      ? null
      : selectedCategories.first;

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
      if (!(selectedCategory?.matchesProduct(product) ??
          (product.categoryId == filterState.selectedCategoryId))) {
        return false;
      }
    }

    // 3. Price Filter
    if (product.dealerPrice < filterState.minPrice ||
        (filterState.maxPrice < 30000 &&
            product.dealerPrice > filterState.maxPrice)) {
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

  // Sort
  switch (filterState.sortOption) {
    case SortOption.priceLowToHigh:
      filtered.sort((a, b) => a.dealerPrice.compareTo(b.dealerPrice));
      break;
    case SortOption.priceHighToLow:
      filtered.sort((a, b) => b.dealerPrice.compareTo(a.dealerPrice));
      break;
    case SortOption.discountHighToLow:
      filtered.sort(
        (a, b) => b.discountPercentage.compareTo(a.discountPercentage),
      );
      break;
    case SortOption.popularity:
      filtered.sort((a, b) => b.rating.compareTo(a.rating));
      break;
    case SortOption.newest:
      filtered.sort((a, b) => b.id.compareTo(a.id));
      break;
  }

  return filtered;
}, dependencies: [productFilterProvider]);
