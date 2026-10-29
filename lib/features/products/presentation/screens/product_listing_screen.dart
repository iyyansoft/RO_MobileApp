import '../widgets/cart_actions.dart';
import '../../domain/models/product_model.dart';
import 'product_details_screen.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/loading_skeleton.dart';
import '../providers/product_provider.dart';
import '../widgets/filter_bottom_sheet.dart';
import '../widgets/product_card.dart';
import '../widgets/sort_bottom_sheet.dart';

class ProductListingScreen extends ConsumerWidget {
  final String? initialCategoryId;
  final String? initialCategoryName;

  const ProductListingScreen({
    super.key,
    this.initialCategoryId,
    this.initialCategoryName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = _ProductListingContent(
      initialCategoryName: initialCategoryName,
    );
    if (initialCategoryId == null) return content;

    final preferences = ref.read(productFilterProvider);
    return ProviderScope(
      overrides: [
        productFilterProvider.overrideWith(
          (ref) => ProductNotifier(
            initialState: ProductFilterState(
              selectedCategoryId: initialCategoryId,
              sortOption: preferences.sortOption,
              isGridView: preferences.isGridView,
            ),
          ),
        ),
      ],
      child: content,
    );
  }
}

class _ProductListingContent extends ConsumerStatefulWidget {
  final String? initialCategoryName;

  const _ProductListingContent({this.initialCategoryName});

  @override
  ConsumerState<_ProductListingContent> createState() =>
      _ProductListingScreenState();
}

class _ProductListingScreenState extends ConsumerState<_ProductListingContent> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();

    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(productFilterProvider.notifier).loadMoreProducts();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? AppColors.accentDark : AppColors.primaryLight;

    final filterState = ref.watch(productFilterProvider);
    final categories = ref.watch(categoriesProvider);
    final products = ref.watch(filteredProductsProvider);

    final activeFilterCount =
        (filterState.selectedCategoryId != null ? 1 : 0) +
        (filterState.inStockOnly ? 1 : 0) +
        filterState.selectedBrands.length +
        ((filterState.minPrice > 0 || filterState.maxPrice < 30000) ? 1 : 0);

    final catalog = ref.watch(catalogProductsProvider);
    if (catalog.hasError) {
      return Scaffold(
        appBar: AppBar(title: const Text('Catalog')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${catalog.error}', textAlign: TextAlign.center),
              TextButton(
                onPressed: () => ref.invalidate(catalogProductsProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: isDark
            ? AppColors.backgroundDark
            : AppColors.backgroundLight,
        title: Text(
          widget.initialCategoryName ?? 'RO Wholesale Catalog',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 17,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        actions: [
          // View Mode Toggle Button (Grid vs List)
          IconButton(
            icon: Icon(
              filterState.isGridView
                  ? Icons.view_list_rounded
                  : Icons.grid_view_rounded,
              color: primaryColor,
            ),
            tooltip: filterState.isGridView
                ? 'Switch to List'
                : 'Switch to Grid',
            onPressed: () {
              ref.read(productFilterProvider.notifier).toggleViewMode();
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 1. Search Bar Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.surfaceDark
                      : AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF1E2D3D)
                        : const Color(0xFFE2E8F0),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) {
                    ref
                        .read(productFilterProvider.notifier)
                        .setSearchQuery(val);
                  },
                  decoration: InputDecoration(
                    hintText: 'Search products, SKU or brands...',
                    hintStyle: const TextStyle(
                      fontSize: 13,
                      color: Colors.grey,
                    ),
                    prefixIcon: Icon(Icons.search_rounded, color: primaryColor),
                    suffixIcon: filterState.searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              ref
                                  .read(productFilterProvider.notifier)
                                  .setSearchQuery('');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),

            // 2. Horizontal Category Choice Chips ScrollBar
            SizedBox(
              height: 44,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                itemCount: categories.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    final isAllSelected =
                        filterState.selectedCategoryId == null;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: const Text('All Products'),
                        selected: isAllSelected,
                        selectedColor: primaryColor,
                        labelStyle: TextStyle(
                          color: isAllSelected
                              ? Colors.white
                              : (isDark ? Colors.white70 : Colors.black87),
                          fontWeight: isAllSelected
                              ? FontWeight.w800
                              : FontWeight.w500,
                          fontSize: 11.5,
                        ),
                        onSelected: (_) {
                          ref
                              .read(productFilterProvider.notifier)
                              .selectCategory(null);
                        },
                      ),
                    );
                  }

                  final cat = categories[index - 1];
                  final isSelected = filterState.selectedCategoryId == cat.id;

                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(cat.name),
                      selected: isSelected,
                      selectedColor: primaryColor,
                      labelStyle: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : (isDark ? Colors.white70 : Colors.black87),
                        fontWeight: isSelected
                            ? FontWeight.w800
                            : FontWeight.w500,
                        fontSize: 11.5,
                      ),
                      onSelected: (_) {
                        ref
                            .read(productFilterProvider.notifier)
                            .selectCategory(cat.id);
                      },
                    ),
                  );
                },
              ),
            ),

            // 3. Filter & Sort Action Toolbar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  // Product Count Text
                  Text(
                    '${products.length} Products',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  // Sort Button
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            backgroundColor: Colors.transparent,
                            builder: (context) => const SortBottomSheet(),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 50),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: Icon(
                          Icons.swap_vert_rounded,
                          size: 16,
                          color: primaryColor,
                        ),
                        label: Text(
                          filterState.sortOption.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Filter Button with Badge
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (context) => const FilterBottomSheet(),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 50),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: Icon(
                          Icons.filter_list_rounded,
                          size: 16,
                          color: primaryColor,
                        ),
                        label: const Text(
                          'Filter',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (activeFilterCount > 0)
                        Positioned(
                          top: -4,
                          right: -4,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Color(0xFFEF4444),
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            child: Center(
                              child: Text(
                                '$activeFilterCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // 4. Main Product Listing Body (With Lazy Loading & Skeleton Loader)
            Expanded(
              child: catalog.isLoading
                  ? _buildSkeletonLoadingGrid(filterState.isGridView)
                  : products.isEmpty
                  ? _buildEmptyState(context, isDark, primaryColor)
                  : filterState.isGridView
                  ? _buildGridView(products, filterState.isLoadingMore)
                  : _buildListView(products, filterState.isLoadingMore),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridView(List products, bool isLoadingMore) {
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.64,
          ),
          itemCount: products.length,
          itemBuilder: (context, index) {
            final product = products[index];
            return ProductCard(
              product: product,
              isGrid: true,
              onTap: () {
                _openProductDetails(context, product);
              },
              onAddToCart: () {
                _handleAddToCart(context, product);
              },
            );
          },
        ),
        if (isLoadingMore) ...[
          const SizedBox(height: 16),
          const Center(child: CircularProgressIndicator.adaptive()),
        ],
      ],
    );
  }

  Widget _buildListView(List products, bool isLoadingMore) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
      itemCount: products.length + (isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == products.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator.adaptive()),
          );
        }
        final product = products[index];
        return ProductCard(
          product: product,
          isGrid: false,
          onTap: () {
            _openProductDetails(context, product);
          },
          onAddToCart: () {
            _handleAddToCart(context, product);
          },
        );
      },
    );
  }

  Widget _buildSkeletonLoadingGrid(bool isGrid) {
    if (!isGrid) {
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 6,
        itemBuilder: (context, index) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: LoadingSkeleton.rectangular(
              width: double.infinity,
              height: 100,
              borderRadius: 16,
            ),
          );
        },
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.64,
      ),
      itemCount: 6,
      itemBuilder: (context, index) {
        return const LoadingSkeleton.rectangular(
          width: double.infinity,
          height: 250,
          borderRadius: 16,
        );
      },
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    bool isDark,
    Color primaryColor,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 64,
              color: primaryColor.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No Products Found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Try adjusting your search keywords, price range, or category filters.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                ref.read(productFilterProvider.notifier).clearFilters();
                _searchController.clear();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Reset All Filters'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _handleAddToCart(BuildContext context, dynamic product) =>
      addProductToCart(context, ref, product);

  void _openProductDetails(BuildContext context, ProductModel product) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (context) => ProductDetailsScreen(product: product),
      ),
    );
  }
}
