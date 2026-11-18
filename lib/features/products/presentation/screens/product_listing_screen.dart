import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/loading_skeleton.dart';
import '../../domain/models/category_model.dart';
import '../../domain/models/product_model.dart';
import '../providers/product_provider.dart';
import '../widgets/cart_actions.dart';
import '../widgets/catalog_listing_widgets.dart';
import '../widgets/filter_bottom_sheet.dart';
import '../widgets/listing_product_card.dart';
import '../widgets/sort_bottom_sheet.dart';
import 'product_details_screen.dart';

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
  static const _maxContentWidth = 1320.0;
  static const _pageBg = Color(0xFFF3F7FC);

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Show any search already applied to this listing.
    _searchController.text = ref.read(productFilterProvider).searchQuery;
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

  /// Opens a bottom sheet that edits THIS listing's filter state (the
  /// category listing has its own scoped provider; a plain modal route would
  /// otherwise edit the app-wide one).
  void _openSheet(Widget sheet, {bool scrollControlled = false}) {
    final container = ProviderScope.containerOf(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: scrollControlled,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          UncontrolledProviderScope(container: container, child: sheet),
    );
  }

  void _back() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      GoRouter.maybeOf(context)?.go('/home');
    }
  }

  void _openCategories() {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.go('/categories');
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filterState = ref.watch(productFilterProvider);
    final categories = ref.watch(categoriesProvider);
    final products = ref.watch(filteredProductsProvider);
    final catalog = ref.watch(catalogProductsProvider);

    if (catalog.hasError && !catalog.hasValue) {
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

    CategoryModel? selected;
    for (final c in categories) {
      if (c.id == filterState.selectedCategoryId ||
          c.databaseId == filterState.selectedCategoryId) {
        selected = c;
        break;
      }
    }
    final title =
        selected?.name ??
        (filterState.selectedCategoryId != null
            ? widget.initialCategoryName
            : null) ??
        'All Products';
    final subtitle = (selected?.description.trim().isNotEmpty ?? false)
        ? selected!.description.trim()
        : 'Genuine RO products at wholesale prices';

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A1118) : _pageBg,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final narrow = width < 600;
            final pad = math.max(
              narrow ? 16.0 : 32.0,
              (width - _maxContentWidth) / 2,
            );
            final contentWidth = width - pad * 2;

            return CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: CatalogHeader(
                    title: title,
                    subtitle: subtitle,
                    icon: categoryIconFor(
                      selected == null
                          ? 'all'
                          : '${selected.id} ${selected.name}',
                    ),
                    onBack: _back,
                    onBreadcrumb: _openCategories,
                    horizontalPadding: pad,
                    isDark: isDark,
                    bottom: _searchBar(isDark, filterState),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(top: narrow ? 16 : 24),
                    child: CategoryChipBar(
                      categories: categories,
                      selectedId:
                          selected?.id ?? filterState.selectedCategoryId,
                      horizontalPadding: pad,
                      isDark: isDark,
                      onSelect: (id) => ref
                          .read(productFilterProvider.notifier)
                          .selectCategory(id),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      pad,
                      narrow ? 18 : 28,
                      pad,
                      narrow ? 16 : 24,
                    ),
                    child: ListingToolbar(
                      count: products.length,
                      isGridView: filterState.isGridView,
                      onViewChanged: (grid) {
                        if (grid != filterState.isGridView) {
                          ref
                              .read(productFilterProvider.notifier)
                              .toggleViewMode();
                        }
                      },
                      sortLabel: filterState.sortOption.label,
                      onSort: () => _openSheet(const SortBottomSheet()),
                      activeFilters: activeFilterCount(filterState),
                      onFilter: () => _openSheet(
                        const FilterBottomSheet(),
                        scrollControlled: true,
                      ),
                      isDark: isDark,
                    ),
                  ),
                ),
                if (catalog.isLoading && !catalog.hasValue)
                  _skeleton(pad, contentWidth, filterState.isGridView)
                else if (products.isEmpty)
                  SliverToBoxAdapter(child: _buildEmptyState(isDark))
                else
                  _products(
                    products,
                    pad,
                    contentWidth,
                    filterState.isGridView,
                    isDark,
                  ),
                if (filterState.isLoadingMore)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: CircularProgressIndicator.adaptive(),
                      ),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 90)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _searchBar(bool isDark, ProductFilterState filterState) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF132233) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF1E2D3D) : const Color(0xFFE3EAF3),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F2850).withValues(alpha: 0.07),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: TextField(
        key: const ValueKey('listing-search'),
        controller: _searchController,
        onChanged: (val) =>
            ref.read(productFilterProvider.notifier).setSearchQuery(val),
        textInputAction: TextInputAction.search,
        style: TextStyle(
          fontSize: 15.5,
          color: isDark ? Colors.white : const Color(0xFF0F172A),
        ),
        decoration: InputDecoration(
          hintText: 'Search products, SKU or brands...',
          hintStyle: const TextStyle(fontSize: 15.5, color: Color(0xFF94A3B8)),
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 18, right: 10),
            child: Icon(
              Icons.search_rounded,
              color: Color(0xFF0B4FB8),
              size: 26,
            ),
          ),
          suffixIcon: filterState.searchQuery.isNotEmpty
              ? IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () {
                    _searchController.clear();
                    ref.read(productFilterProvider.notifier).setSearchQuery('');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 20),
        ),
      ),
    );
  }

  /// Columns: grid 3 (desktop) / 2 (tablet) / 1 (phone); list = 1.
  int _columns(double contentWidth, bool grid) =>
      !grid ? 1 : (contentWidth >= 1000 ? 3 : (contentWidth >= 640 ? 2 : 1));

  Widget _products(
    List<ProductModel> products,
    double pad,
    double contentWidth,
    bool grid,
    bool isDark,
  ) {
    final columns = _columns(contentWidth, grid);
    final spacing = contentWidth < 600 ? 16.0 : 24.0;
    final cardWidth = (contentWidth - spacing * (columns - 1)) / columns;
    // List view: wide rows on tablet/desktop; phones keep the tile.
    final rows = !grid && contentWidth >= 760;
    final extent = rows
        ? ListingProductCard.rowExtentFor(products)
        : ListingProductCard.tileExtent(cardWidth);

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: pad),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: spacing,
          mainAxisSpacing: spacing,
          mainAxisExtent: extent,
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          final product = products[index];
          return ListingProductCard(
            key: ValueKey('listing-card-${product.id}'),
            product: product,
            layout: rows ? ListingCardLayout.row : ListingCardLayout.tile,
            isDark: isDark,
            onTap: () => _openProductDetails(product),
            onAddToCart: (qty) =>
                addProductToCart(context, ref, product, quantity: qty),
          );
        }, childCount: products.length),
      ),
    );
  }

  Widget _skeleton(double pad, double contentWidth, bool grid) {
    final columns = _columns(contentWidth, grid);
    final spacing = contentWidth < 600 ? 16.0 : 24.0;
    final cardWidth = (contentWidth - spacing * (columns - 1)) / columns;
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: pad),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: spacing,
          mainAxisSpacing: spacing,
          mainAxisExtent: ListingProductCard.tileExtent(cardWidth),
        ),
        delegate: SliverChildBuilderDelegate(
          (_, __) => const LoadingSkeleton.rectangular(
            width: double.infinity,
            height: double.infinity,
            borderRadius: 22,
          ),
          childCount: columns * 2,
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFF0B4FB8).withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.search_off_rounded,
              size: 36,
              color: Color(0xFF0B4FB8),
            ),
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
            style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              ref.read(productFilterProvider.notifier).clearFilters();
              _searchController.clear();
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0B4FB8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Reset All Filters'),
          ),
        ],
      ),
    );
  }

  void _openProductDetails(ProductModel product) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (context) => ProductDetailsScreen(product: product),
      ),
    );
  }
}
