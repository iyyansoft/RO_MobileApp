import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    this.isGridView = true,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.page = 1,
    this.hasMore = true,
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
      selectedCategoryId: clearCategory ? null : (selectedCategoryId ?? this.selectedCategoryId),
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
  ProductNotifier() : super(const ProductFilterState());

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query, page: 1, hasMore: true);
  }

  void selectCategory(String? categoryId) {
    if (categoryId == null) {
      state = state.copyWith(clearCategory: true, page: 1, hasMore: true);
    } else {
      state = state.copyWith(selectedCategoryId: categoryId, page: 1, hasMore: true);
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

    // Simulate lazy loading pagination delay
    await Future.delayed(const Duration(milliseconds: 600));

    if (state.page >= 3) {
      state = state.copyWith(isLoadingMore: false, hasMore: false);
    } else {
      state = state.copyWith(
        isLoadingMore: false,
        page: state.page + 1,
      );
    }
  }
}

final productFilterProvider =
    StateNotifierProvider<ProductNotifier, ProductFilterState>((ref) {
  return ProductNotifier();
});

final categoriesProvider = Provider<List<CategoryModel>>((ref) {
  return CategoryModel.defaultCategories;
});

final allProductsProvider = Provider<List<ProductModel>>((ref) {
  return ProductModel.sampleProducts;
});

final filteredProductsProvider = Provider<List<ProductModel>>((ref) {
  final filterState = ref.watch(productFilterProvider);
  final allProducts = ref.watch(allProductsProvider);

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
      if (product.categoryId != filterState.selectedCategoryId) {
        return false;
      }
    }

    // 3. Price Filter
    if (product.dealerPrice < filterState.minPrice ||
        product.dealerPrice > filterState.maxPrice) {
      return false;
    }

    // 4. In Stock Filter
    if (filterState.inStockOnly && product.stockStatus == StockStatus.outOfStock) {
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
      filtered.sort((a, b) => b.discountPercentage.compareTo(a.discountPercentage));
      break;
    case SortOption.popularity:
      filtered.sort((a, b) => b.rating.compareTo(a.rating));
      break;
    case SortOption.newest:
      filtered.sort((a, b) => b.id.compareTo(a.id));
      break;
  }

  return filtered;
});
