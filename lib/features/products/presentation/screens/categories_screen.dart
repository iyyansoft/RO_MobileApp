import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_image.dart';
import '../../../../core/widgets/category_image.dart';
import '../../../../core/network/api_client.dart';
import '../../../cart/presentation/providers/cart_provider.dart';
import '../../../cart/presentation/screens/cart_screen.dart';
import '../../domain/models/category_model.dart';
import '../../domain/models/product_model.dart';
import '../providers/product_provider.dart';
import 'product_details_screen.dart';
import 'product_listing_screen.dart';

class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  // 'for_you' is the default selected category matching reference image
  String _selectedCategoryId = 'for_you';
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _sidebarScrollController = ScrollController();
  final ScrollController _contentScrollController = ScrollController();
  String _searchQuery = '';
  bool _isSearchExpanded = false;

  @override
  void dispose() {
    _searchController.dispose();
    _sidebarScrollController.dispose();
    _contentScrollController.dispose();
    super.dispose();
  }

  void _selectCategory(String id) {
    if (_selectedCategoryId != id) {
      setState(() {
        _selectedCategoryId = id;
      });
      if (_contentScrollController.hasClients) {
        _contentScrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  void _openCart(BuildContext context) {
    try {
      context.go('/cart');
    } catch (_) {
      Navigator.of(
        context,
        rootNavigator: true,
      ).push(MaterialPageRoute(builder: (context) => const CartScreen()));
    }
  }

  void _openProduct(BuildContext context, ProductModel product) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (context) => ProductDetailsScreen(product: product),
      ),
    );
  }

  void _openFullListing(
    BuildContext context, {
    String? categoryId,
    String? categoryName,
  }) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (context) => ProductListingScreen(
          initialCategoryId: categoryId,
          initialCategoryName: categoryName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? AppColors.accentDark : AppColors.primaryLight;
    final surfaceColor = isDark ? AppColors.surfaceDark : Colors.white;
    final sidebarBg = isDark
        ? const Color(0xFF0C1420)
        : const Color(0xFFF7F9FC);
    final borderColor = isDark
        ? const Color(0xFF1E2D3D)
        : const Color(0xFFE5E9F0);

    final catalog = ref.watch(catalogCategoriesProvider);
    final productCatalog = ref.watch(catalogProductsProvider);
    final allCategories = ref.watch(categoriesProvider);
    final allProducts = ref.watch(allProductsProvider);
    final cartState = ref.watch(cartProvider);
    final cartCount = cartState.totalItemCount;

    if (catalog.isLoading || productCatalog.isLoading) {
      return Scaffold(
        backgroundColor: surfaceColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (catalog.hasError || productCatalog.hasError) {
      return Scaffold(
        backgroundColor: surfaceColor,
        appBar: AppBar(title: const Text('Categories'), elevation: 0),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 48,
                  color: AppColors.errorLight,
                ),
                const SizedBox(height: 12),
                Text(
                  '${catalog.error ?? productCatalog.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    ref.invalidate(catalogCategoriesProvider);
                    ref.invalidate(catalogProductsProvider);
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Filter products on search
    final filteredProducts = _searchQuery.isEmpty
        ? allProducts
        : allProducts.where((p) {
            final q = _searchQuery.toLowerCase();
            return p.name.toLowerCase().contains(q) ||
                p.categoryName.toLowerCase().contains(q) ||
                p.brand.toLowerCase().contains(q) ||
                p.sku.toLowerCase().contains(q);
          }).toList();

    return Scaffold(
      backgroundColor: surfaceColor,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: _buildTopBar(
          context,
          isDark: isDark,
          primaryColor: primaryColor,
          cartCount: cartCount,
          surfaceColor: surfaceColor,
          borderColor: borderColor,
        ),
      ),
      body: SafeArea(
        top: false,
        child: Row(
          children: [
            // Left sidebar: width scales with screen size
            Container(
              width: _sidebarWidth(context),
              decoration: BoxDecoration(
                color: sidebarBg,
                border: Border(right: BorderSide(color: borderColor, width: 1)),
              ),
              child: ListView(
                controller: _sidebarScrollController,
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [
                  // "For You" item
                  _buildSidebarItem(
                    id: 'for_you',
                    title: 'For You',
                    isSelected: _selectedCategoryId == 'for_you',
                    isDark: isDark,
                    primaryColor: primaryColor,
                    customIcon: Container(
                      width: _sidebarThumbSize(context),
                      height: _sidebarThumbSize(context),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF8EC5FC), Color(0xFF5B86E5)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF5B86E5)
                                .withValues(alpha: 0.25),
                            blurRadius: 5,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(
                          Icons.local_mall_rounded,
                          color: Colors.white,
                          size: _sidebarThumbSize(context) * 0.5,
                        ),
                      ),
                    ),
                  ),

                  // Real RO Categories
                  ...allCategories.map((cat) {
                    final localImg = _getCategoryLocalImage(cat.name, cat.id);
                    return _buildSidebarItem(
                      id: cat.id,
                      title: cat.name,
                      isSelected: _selectedCategoryId == cat.id,
                      isDark: isDark,
                      primaryColor: primaryColor,
                      localImagePath: localImg,
                      imagePath: cat.imagePath,
                      fallbackIcon: _getCategoryFallbackIcon(cat.name, cat.id),
                    );
                  }),
                ],
              ),
            ),

            // Right main content area with LayoutBuilder for responsive calculations
            Expanded(
              child: Container(
                color: isDark ? AppColors.backgroundDark : Colors.white,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final availableWidth = constraints.maxWidth;
                    final int crossAxisCount = availableWidth > 1000
                        ? 5
                        : (availableWidth > 650 ? 4 : 3);
                    const hPadding = 10.0;
                    const spacing = 8.0;
                    final cardWidth =
                        (availableWidth -
                            (hPadding * 2) -
                            ((crossAxisCount - 1) * spacing)) /
                        crossAxisCount;
                    // Bounded card height: square image (cardWidth) + 50px for title + price + gaps
                    final cardHeight = cardWidth + 50.0;
                    final childAspectRatio = (cardWidth / cardHeight).clamp(
                      0.60,
                      0.75,
                    );

                    if (_searchQuery.isNotEmpty) {
                      return _buildSearchResults(
                        context,
                        filteredProducts,
                        isDark,
                        primaryColor,
                        childAspectRatio,
                        crossAxisCount,
                      );
                    }

                    if (_selectedCategoryId == 'for_you') {
                      return _buildForYouContent(
                        context,
                        allCategories,
                        allProducts,
                        isDark,
                        primaryColor,
                        childAspectRatio,
                        crossAxisCount,
                      );
                    }

                    return _buildSelectedCategoryContent(
                      context,
                      allCategories,
                      allProducts,
                      isDark,
                      primaryColor,
                      childAspectRatio,
                      crossAxisCount,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- TOP BAR ---
  Widget _buildTopBar(
    BuildContext context, {
    required bool isDark,
    required Color primaryColor,
    required int cartCount,
    required Color surfaceColor,
    required Color borderColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        border: Border(bottom: BorderSide(color: borderColor, width: 0.8)),
      ),
      child: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 16,
        title: _isSearchExpanded
            ? TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val.trim();
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Search RO filters, pumps, membranes...',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : const Color(0xFF94A3B8),
                  ),
                  border: InputBorder.none,
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: primaryColor,
                    size: 20,
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _searchQuery = '';
                        _isSearchExpanded = false;
                      });
                    },
                  ),
                ),
              )
            : Text(
                'All Categories',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 19,
                  letterSpacing: -0.4,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
        actions: [
          if (!_isSearchExpanded)
            IconButton(
              icon: Icon(
                Icons.search_rounded,
                size: 23,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
              tooltip: 'Search',
              onPressed: () {
                setState(() {
                  _isSearchExpanded = true;
                });
              },
            ),
          // Cart Button with Red Badge
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: Icon(
                  Icons.shopping_cart_outlined,
                  size: 23,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
                tooltip: 'Cart',
                onPressed: () => _openCart(context),
              ),
              if (cartCount > 0)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE53935),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFE53935)
                              .withValues(alpha: 0.35),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Text(
                      cartCount > 99 ? '99+' : '$cartCount',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }

  // --- COMPACT SIDEBAR ITEM ---
  Widget _buildSidebarItem({
    required String id,
    required String title,
    required bool isSelected,
    required bool isDark,
    required Color primaryColor,
    String? localImagePath,
    String? imagePath,
    IconData? fallbackIcon,
    Widget? customIcon,
  }) {
    final tileBg = isSelected
        ? (isDark ? AppColors.surfaceDark : Colors.white)
        : Colors.transparent;

    Widget buildThumb() {
      if (customIcon != null) return customIcon;

      // Build inner content: local asset > network > icon
      Widget inner;
      if (localImagePath != null) {
        inner = Padding(
          padding: const EdgeInsets.all(3),
          child: CategoryImage(
            url: localImagePath,
            fallback: Icon(
              fallbackIcon ?? Icons.water_drop_rounded,
              size: 20,
              color: isSelected
                  ? primaryColor
                  : (isDark
                        ? AppColors.textSecondaryDark
                        : const Color(0xFF64748B)),
            ),
          ),
        );
      } else if (imagePath != null && imagePath.isNotEmpty) {
        inner = AppImage(
          imagePath,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) => Icon(
            fallbackIcon ?? Icons.water_drop_rounded,
            size: 20,
            color: isSelected
                ? primaryColor
                : (isDark
                      ? AppColors.textSecondaryDark
                      : const Color(0xFF64748B)),
          ),
        );
      } else {
        inner = Center(
          child: Icon(
            fallbackIcon ?? Icons.water_drop_rounded,
            size: 20,
            color: isSelected
                ? primaryColor
                : (isDark
                      ? AppColors.textSecondaryDark
                      : const Color(0xFF64748B)),
          ),
        );
      }

      final thumbSize = _sidebarThumbSize(context);
      return Container(
        width: thumbSize,
        height: thumbSize,
        decoration: BoxDecoration(
          color: localImagePath != null
              ? Colors.white
              : isSelected
              ? (isDark
                    ? primaryColor.withValues(alpha: 0.18)
                    : const Color(0xFFEEF4FF))
              : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? primaryColor.withValues(alpha: 0.3)
                : (isDark ? const Color(0xFF243242) : const Color(0xFFE2E8F0)),
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: ClipRRect(borderRadius: BorderRadius.circular(11), child: inner),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _selectCategory(id),
        child: Container(
          decoration: BoxDecoration(
            color: tileBg,
            border: Border(
              bottom: BorderSide(
                color: isDark
                    ? const Color(0xFF1E2D3D).withValues(alpha: 0.4)
                    : const Color(0xFFE5E9F0).withValues(alpha: 0.4),
                width: 0.5,
              ),
            ),
          ),
          child: Stack(
            children: [
              // Left blue indicator bar
              if (isSelected)
                Positioned(
                  left: 0,
                  top: 8,
                  bottom: 8,
                  child: Container(
                    width: 3.5,
                    decoration: BoxDecoration(
                      color: primaryColor,
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(3),
                      ),
                    ),
                  ),
                ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    buildThumb(),
                    const SizedBox(height: 6),
                    // Label
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: _sidebarLabelSize(context),
                        fontWeight: isSelected
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: isSelected
                            ? primaryColor
                            : (isDark
                                  ? AppColors.textSecondaryDark
                                  : const Color(0xFF64748B)),
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- "FOR YOU" CONTENT ---
  Widget _buildForYouContent(
    BuildContext context,
    List<CategoryModel> categories,
    List<ProductModel> products,
    bool isDark,
    Color primaryColor,
    double childAspectRatio,
    int crossAxisCount,
  ) {
    final popularCategories = categories.take(6).toList();
    final launchProducts = products.take(8).toList();

    return SingleChildScrollView(
      controller: _contentScrollController,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section 1: Popular Store
          Text(
            'Popular Store',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 10),

          // Popular Store grid: 4 per row on desktop, 3 on tablet, 2 on phones.
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final columns = width >= 700 ? 4 : (width >= 420 ? 3 : 2);
              const spacing = 14.0;
              final tileWidth = (width - spacing * (columns - 1)) / columns;
              // Near-square image card + room for the label underneath.
              final tileHeight = tileWidth * 0.92 + 30;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: popularCategories.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: spacing,
                  mainAxisSpacing: spacing,
                  childAspectRatio: tileWidth / tileHeight,
                ),
                itemBuilder: (context, index) {
                  final cat = popularCategories[index];
                  return _buildPopularStoreTile(
                    context,
                    cat: cat,
                    index: index,
                    isDark: isDark,
                    primaryColor: primaryColor,
                  );
                },
              );
            },
          ),

          const SizedBox(height: 20),

          // Section 2: New & Upcoming Launches
          Text(
            'New & Upcoming Launches',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 10),

          // Adaptive Grid for Launches
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: launchProducts.length + 1,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 8,
              mainAxisSpacing: 12,
              childAspectRatio: childAspectRatio,
            ),
            itemBuilder: (context, index) {
              if (index == launchProducts.length) {
                return _buildViewAllCard(
                  context,
                  isDark: isDark,
                  primaryColor: primaryColor,
                  onTap: () => _openFullListing(context),
                );
              }
              final product = launchProducts[index];
              return _buildProductCard(
                context,
                product: product,
                badgeText: _getProductBadge(index),
                isDark: isDark,
                primaryColor: primaryColor,
              );
            },
          ),
        ],
      ),
    );
  }

  // --- SELECTED CATEGORY CONTENT ---
  Widget _buildSelectedCategoryContent(
    BuildContext context,
    List<CategoryModel> categories,
    List<ProductModel> products,
    bool isDark,
    Color primaryColor,
    double childAspectRatio,
    int crossAxisCount,
  ) {
    final currentCategory = categories.firstWhere(
      (c) => c.id == _selectedCategoryId,
      orElse: () => categories.first,
    );

    final categoryProducts = products
        .where((p) => currentCategory.matchesProduct(p))
        .toList();

    return SingleChildScrollView(
      controller: _contentScrollController,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentCategory.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${categoryProducts.length} Wholesale Items Available',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : const Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: () => _openFullListing(
                  context,
                  categoryId: currentCategory.id,
                  categoryName: currentCategory.name,
                ),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'View All',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: primaryColor,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 10,
                        color: primaryColor,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Responsive Products Grid
          if (categoryProducts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 44,
                      color: isDark ? Colors.white24 : Colors.grey.shade400,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'No products in ${currentCategory.name} yet',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => _openFullListing(context),
                      child: const Text('Browse All Products'),
                    ),
                  ],
                ),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: categoryProducts.length + 1,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 8,
                mainAxisSpacing: 12,
                childAspectRatio: childAspectRatio,
              ),
              itemBuilder: (context, index) {
                if (index == categoryProducts.length) {
                  return _buildViewAllCard(
                    context,
                    isDark: isDark,
                    primaryColor: primaryColor,
                    onTap: () => _openFullListing(
                      context,
                      categoryId: currentCategory.id,
                      categoryName: currentCategory.name,
                    ),
                  );
                }
                final product = categoryProducts[index];
                return _buildProductCard(
                  context,
                  product: product,
                  badgeText: _getProductBadge(index),
                  isDark: isDark,
                  primaryColor: primaryColor,
                );
              },
            ),
        ],
      ),
    );
  }

  // --- SEARCH RESULTS ---
  Widget _buildSearchResults(
    BuildContext context,
    List<ProductModel> searchResults,
    bool isDark,
    Color primaryColor,
    double childAspectRatio,
    int crossAxisCount,
  ) {
    return SingleChildScrollView(
      controller: _contentScrollController,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Results for "$_searchQuery"',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
              ),
              Text(
                '${searchResults.length} found',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: primaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (searchResults.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.search_off_rounded,
                      size: 48,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'No products match "$_searchQuery"',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                          _isSearchExpanded = false;
                        });
                      },
                      child: const Text('Clear search'),
                    ),
                  ],
                ),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: searchResults.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 8,
                mainAxisSpacing: 12,
                childAspectRatio: childAspectRatio,
              ),
              itemBuilder: (context, index) {
                final product = searchResults[index];
                return _buildProductCard(
                  context,
                  product: product,
                  badgeText: _getProductBadge(index),
                  isDark: isDark,
                  primaryColor: primaryColor,
                );
              },
            ),
        ],
      ),
    );
  }

  /// Maps a category name/id to its image URL on the app's server
  /// (served from assets/images/ by server.js at /images/<filename>).
  String? _getCategoryLocalImage(String name, String id) {
    final key = '${name.toLowerCase()} ${id.toLowerCase()}';
    if (key.contains('sys') ||
        key.contains('purifier') ||
        key.contains('cabinet')) {
      return ApiClient.imageUrl('RO_System.png');
    }
    if (key.contains('mem')) {
      return ApiClient.imageUrl('membrane.webp');
    }
    if (key.contains('filter') ||
        key.contains('cartridge') ||
        key.contains('carbon') ||
        key.contains('flt')) {
      return ApiClient.imageUrl('filter.jpg');
    }
    if (key.contains('pump') ||
        key.contains('booster') ||
        key.contains('pmp')) {
      return ApiClient.imageUrl('pumps.webp');
    }
    if (key.contains('pipe') ||
        key.contains('tube') ||
        key.contains('tubing') ||
        key.contains('pip')) {
      return ApiClient.imageUrl('tubes.jpg');
    }
    if (key.contains('spare') ||
        key.contains('valve') ||
        key.contains('part') ||
        key.contains('smps')) {
      return ApiClient.imageUrl('spare_parts.jpg');
    }
    return null;
  }

  // --- POPULAR STORE TILE ---
  Widget _buildPopularStoreTile(
    BuildContext context, {
    required CategoryModel cat,
    required int index,
    required bool isDark,
    required Color primaryColor,
  }) {
    final pastelGradients = [
      const LinearGradient(
        colors: [Color(0xFFDCEEFF), Color(0xFFEBF5FF)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      const LinearGradient(
        colors: [Color(0xFFFFF0D6), Color(0xFFFFF8EC)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      const LinearGradient(
        colors: [Color(0xFFEEDEFF), Color(0xFFF5EDFF)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      const LinearGradient(
        colors: [Color(0xFFFEEFBB), Color(0xFFFEF8DC)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      const LinearGradient(
        colors: [Color(0xFFCFE9FF), Color(0xFFE0F4FF)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      const LinearGradient(
        colors: [Color(0xFFBDF5D6), Color(0xFFDCFCEE)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ];
    final darkCardColor = const Color(0xFF162334);

    final localImage = _getCategoryLocalImage(cat.name, cat.id);

    Widget buildCardImage() {
      if (localImage != null) {
        // Product photos have white backgrounds: show them whole (no crop)
        // on a white panel inset within the pastel card.
        return Padding(
          padding: const EdgeInsets.all(10),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: CategoryImage(
                  url: localImage,
                  fallback: Center(
                    child: Icon(
                      _getCategoryFallbackIcon(cat.name, cat.id),
                      color: primaryColor,
                      size: 32,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }
      if (cat.imagePath.isNotEmpty) {
        return AppImage(
          cat.imagePath,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) => Center(
            child: Icon(
              _getCategoryFallbackIcon(cat.name, cat.id),
              color: primaryColor,
              size: 32,
            ),
          ),
        );
      }
      return Center(
        child: Icon(
          _getCategoryFallbackIcon(cat.name, cat.id),
          color: primaryColor,
          size: 32,
        ),
      );
    }

    return GestureDetector(
      onTap: () => _selectCategory(cat.id),
      child: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: isDark
                    ? null
                    : pastelGradients[index % pastelGradients.length],
                color: isDark ? darkCardColor : null,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF23354A)
                      : Colors.black.withValues(alpha: 0.05),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.12 : 0.05),
                    blurRadius: 10,
                    spreadRadius: 0,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Full-bleed product image
                  buildCardImage(),
                  // Subtle bottom scrim for label readability
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 42,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withValues(
                              alpha: isDark ? 0.45 : 0.22,
                            ),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            cat.name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }

  // --- PRODUCT CARD (PERFECTLY BOUNDED, NO OVERFLOW) ---
  Widget _buildProductCard(
    BuildContext context, {
    required ProductModel product,
    required String badgeText,
    required bool isDark,
    required Color primaryColor,
  }) {
    return GestureDetector(
      onTap: () => _openProduct(context, product),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Square image container with teal pill badge
          AspectRatio(
            aspectRatio: 1.0,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF142234)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF22354B)
                      : const Color(0xFFEAEFF5),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  // Product Image
                  Padding(
                    padding: const EdgeInsets.fromLTRB(5, 5, 5, 10),
                    child: AppImage(
                      product.displayImageUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stack) => Center(
                        child: Icon(
                          Icons.water_drop_outlined,
                          size: 24,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ),
                  ),

                  // Teal status pill badge
                  Positioned(
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D7C66),
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0D7C66)
                                .withValues(alpha: 0.25),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Text(
                        badgeText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 7.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 6),

          // 2-line bounded product name
          SizedBox(
            height: 26,
            child: Text(
              product.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                height: 1.15,
                color: isDark ? Colors.white : const Color(0xFF1E293B),
              ),
            ),
          ),

          const SizedBox(height: 2),

          // Wholesale Dealer Price (FittedBox prevents any horizontal text clipping)
          SizedBox(
            height: 16,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '₹${product.dealerPrice.toInt()}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: primaryColor,
                    ),
                  ),
                  if (product.mrp > product.dealerPrice) ...[
                    const SizedBox(width: 3),
                    Text(
                      '₹${product.mrp.toInt()}',
                      style: const TextStyle(
                        fontSize: 9,
                        color: Color(0xFF94A3B8),
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- "VIEW ALL" CIRCULAR TILE ---
  Widget _buildViewAllCard(
    BuildContext context, {
    required bool isDark,
    required Color primaryColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AspectRatio(
            aspectRatio: 1.0,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF142234)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF22354B)
                      : const Color(0xFFE2E8F0),
                  width: 1,
                ),
              ),
              child: Center(
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isDark
                        ? primaryColor.withValues(alpha: 0.2)
                        : const Color(0xFFEBF3FF),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.arrow_downward_rounded,
                    color: primaryColor,
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 26,
            child: Center(
              child: Text(
                'View All',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- HELPER: Badge text generator ---
  String _getProductBadge(int index) {
    const badges = [
      'NEW LAUNCH',
      'BUY NOW',
      'WHOLESALE',
      'SALE IS LIVE',
      'BEST VALUE',
      'IN STOCK',
      'TOP PICK',
    ];
    return badges[index % badges.length];
  }

  // --- HELPER: Responsive sidebar sizing (phone / tablet / desktop) ---
  double _sidebarWidth(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= 1024 ? 112 : (w >= 600 ? 96 : 84);
  }

  double _sidebarThumbSize(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= 1024 ? 62 : (w >= 600 ? 56 : 50);
  }

  double _sidebarLabelSize(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= 1024 ? 12 : (w >= 600 ? 11.5 : 10.5);
  }

  // --- HELPER: Category fallback icons ---
  IconData _getCategoryFallbackIcon(String name, String id) {
    final key = '${name.toLowerCase()} ${id.toLowerCase()}';
    if (key.contains('system') ||
        key.contains('purifier') ||
        key.contains('cabinet')) {
      return Icons.kitchen_rounded;
    }
    if (key.contains('membrane')) {
      return Icons.layers_rounded;
    }
    if (key.contains('pump') || key.contains('booster')) {
      return Icons.speed_rounded;
    }
    if (key.contains('filter') ||
        key.contains('cartridge') ||
        key.contains('carbon')) {
      return Icons.filter_alt_rounded;
    }
    if (key.contains('pipe') ||
        key.contains('tube') ||
        key.contains('tubing')) {
      return Icons.timeline_rounded;
    }
    if (key.contains('spare') ||
        key.contains('valve') ||
        key.contains('smps')) {
      return Icons.handyman_rounded;
    }
    return Icons.water_drop_rounded;
  }
}
