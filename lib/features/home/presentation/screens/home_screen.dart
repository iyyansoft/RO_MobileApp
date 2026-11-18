import '../../../products/presentation/widgets/cart_actions.dart';
import '../../../../core/widgets/app_image.dart';
import '../../../../core/widgets/category_image.dart';
import '../widgets/hero_carousel/hero_banner_carousel.dart';
import '../widgets/home_search_bar.dart';
import '../../../products/presentation/widgets/filter_bottom_sheet.dart';
import '../widgets/quick_action_tile.dart';
import '../widgets/home_product_card.dart';
import '../widgets/wholesale_promo_banner.dart';
import '../widgets/home_footer.dart';
import '../widgets/why_choose_section.dart';
import '../../../../core/network/api_client.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/brand_logo.dart';
import '../../../../core/widgets/loading_skeleton.dart';
import '../../../../core/widgets/responsive_layout.dart';
import '../../../cart/presentation/providers/cart_provider.dart';
import '../../../products/domain/models/category_model.dart';
import '../../../products/domain/models/product_model.dart';
import '../../../products/presentation/providers/product_provider.dart';
import '../../../products/presentation/screens/product_details_screen.dart';
import '../../../products/presentation/screens/product_listing_screen.dart';
import '../../domain/home_best_sellers.dart';
import '../widgets/home_product_carousel.dart';
import '../../../products/domain/cabinet_display_order.dart';

const _homeBlue = AppColors.primaryLight;

void _pushHomeRoute(
  BuildContext context,
  Widget page, {
  bool useRootNavigator = true,
}) {
  Navigator.of(
    context,
    rootNavigator: useRootNavigator,
  ).push<void>(MaterialPageRoute<void>(builder: (_) => page));
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeHeaderWavePainter extends CustomPainter {
  const _HomeHeaderWavePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final backWave = Path()
      ..moveTo(0, size.height * .57)
      ..cubicTo(
        size.width * .2,
        size.height * .35,
        size.width * .4,
        size.height * .76,
        size.width * .61,
        size.height * .55,
      )
      ..cubicTo(
        size.width * .78,
        size.height * .36,
        size.width * .9,
        size.height * .69,
        size.width,
        size.height * .5,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(backWave, Paint()..color = const Color(0x66B7E6FF));

    final frontWave = Path()
      ..moveTo(0, size.height * .77)
      ..cubicTo(
        size.width * .2,
        size.height * .61,
        size.width * .4,
        size.height * .93,
        size.width * .62,
        size.height * .74,
      )
      ..cubicTo(
        size.width * .78,
        size.height * .62,
        size.width * .9,
        size.height * .88,
        size.width,
        size.height * .74,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(frontWave, Paint()..color = const Color(0x66D9F3FF));

    final highlight = Path()
      ..moveTo(0, size.height * .77)
      ..cubicTo(
        size.width * .2,
        size.height * .61,
        size.width * .4,
        size.height * .93,
        size.width * .62,
        size.height * .74,
      )
      ..cubicTo(
        size.width * .78,
        size.height * .62,
        size.width * .9,
        size.height * .88,
        size.width,
        size.height * .74,
      );
    canvas.drawPath(
      highlight,
      Paint()
        ..color = const Color(0xB3FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    final bubbleStroke = Paint()
      ..color = const Color(0x668CCFEB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final bubbleFill = Paint()..color = const Color(0x33FFFFFF);
    for (final (x, y, radius) in [
      (0.08, 0.2, 3.0),
      (0.59, 0.16, 2.4),
      (0.7, 0.83, 3.2),
      (0.94, 0.35, 2.2),
    ]) {
      final center = Offset(size.width * x, size.height * y);
      canvas.drawCircle(center, radius, bubbleFill);
      canvas.drawCircle(center, radius, bubbleStroke);
      canvas.drawCircle(
        center.translate(-radius * .2, -radius * .2),
        radius * .22,
        Paint()..color = const Color(0x99FFFFFF),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HomeHeaderWavePainter oldDelegate) => false;
}

class _WaterWavePageBackgroundPainter extends CustomPainter {
  final bool isDark;
  const _WaterWavePageBackgroundPainter({this.isDark = false});

  @override
  void paint(Canvas canvas, Size size) {
    if (isDark) return;

    // 1. Left side flowing water wave
    final leftWave = Path()
      ..moveTo(0, size.height * 0.04)
      ..cubicTo(
        size.width * 0.14,
        size.height * 0.16,
        size.width * 0.02,
        size.height * 0.36,
        size.width * 0.09,
        size.height * 0.52,
      )
      ..cubicTo(
        size.width * 0.16,
        size.height * 0.68,
        size.width * 0.04,
        size.height * 0.84,
        0,
        size.height * 0.94,
      )
      ..close();

    final leftPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0x35BAE6FD), Color(0x187DD3FC), Color(0x00E0F2FE)],
      ).createShader(Rect.fromLTWH(0, 0, size.width * 0.22, size.height));
    canvas.drawPath(leftWave, leftPaint);

    // 2. Right side flowing water wave
    final rightWave = Path()
      ..moveTo(size.width, size.height * 0.08)
      ..cubicTo(
        size.width * 0.86,
        size.height * 0.20,
        size.width * 0.98,
        size.height * 0.40,
        size.width * 0.91,
        size.height * 0.58,
      )
      ..cubicTo(
        size.width * 0.84,
        size.height * 0.74,
        size.width * 0.96,
        size.height * 0.88,
        size.width,
        size.height,
      )
      ..close();

    final rightPaint = Paint()
      ..shader =
          const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0x30BAE6FD), Color(0x1538BDF8), Color(0x00E0F2FE)],
          ).createShader(
            Rect.fromLTWH(size.width * 0.78, 0, size.width * 0.22, size.height),
          );
    canvas.drawPath(rightWave, rightPaint);

    // 3. Ambient ripples and water bubbles
    final ripplePaint = Paint()
      ..color = const Color(0x1C0284C7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(
      Offset(size.width * 0.05, size.height * 0.24),
      40,
      ripplePaint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.94, size.height * 0.46),
      60,
      ripplePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _WaterWavePageBackgroundPainter oldDelegate) =>
      false;
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark
        ? const Color(0xFF00F5D4)
        : const Color(0xFF0F4C81);
    final categories = ref.watch(categoriesProvider);
    final allProducts = ref.watch(allProductsProvider);

    final featuredProducts = allProducts.where((p) => p.isFeatured).isNotEmpty
        ? allProducts.where((p) => p.isFeatured).toList()
        : allProducts.where((p) => p.discountPercentage > 0).take(4).toList();
    // Best Sellers: the Cabinet category page's products, in its order, from
    // the same (auto-refreshed) catalogue, as a horizontal slider. View All
    // opens that page. Without a Cabinet category: the previous rule.
    final cabinetProducts = ref.watch(cabinetCategoryProductsProvider);
    final bestSellersAreCabinets = cabinetProducts.isNotEmpty;
    final bestSellers = bestSellersAreCabinets
        ? cabinetProducts
        : homeBestSellersFallback(allProducts);
    final cabinetMatches = categories.where(isCabinetCategory);
    final cabinetCategory = cabinetMatches.isEmpty
        ? null
        : cabinetMatches.first;
    // /api/products is ordered by category and name, so order by the date
    // each product was added to surface products just created by the admin.
    final newArrivals = ProductModel.newestFirst(allProducts);
    final wholesaleDeals = allProducts.where((p) => p.moq >= 10).toList();

    final catalog = ref.watch(catalogProductsProvider);
    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0A1118)
          : const Color(0xFFF7FBFC),
      body: Stack(
        children: [
          // Background Gradient & Water Wave Effects
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: isDark
                      ? [const Color(0xFF0A1118), const Color(0xFF0F1A24)]
                      : [
                          const Color(0xFFEAF5FE),
                          const Color(0xFFF8FCFF),
                          const Color(0xFFFFFFFF),
                        ],
                  stops: const [0.0, 0.35, 1.0],
                ),
              ),
              child: CustomPaint(
                painter: _WaterWavePageBackgroundPainter(isDark: isDark),
              ),
            ),
          ),
          // bottom: false: the navigation shell already keeps content above
          // the bottom bar and the system gesture area.
          SafeArea(
            bottom: false,
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(catalogCategoriesProvider);
                ref.invalidate(catalogProductsProvider);
                await ref.read(catalogProductsProvider.future);
              },
              child: SingleChildScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    ResponsiveContentWrapper(
                      maxWidth: 1240,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. PREMIUM REDESIGNED APP HEADER (Branding & Action Buttons)
                          _buildHeader(context),

                          // Search + quick actions (always available, even
                          // while the catalogue is still loading).
                          _buildTopSection(context, isDark),

                          if (catalog.isLoading && !catalog.hasValue)
                            _buildSkeletonDashboard()
                          else if (catalog.hasError && !catalog.hasValue)
                            _buildCatalogError(catalog.error)
                          else ...[
                            HeroBannerCarousel(
                              onNavigate: (route) => context.go(route),
                            ),

                            // 1. Categories Section
                            _buildSectionHeader(
                              context,
                              title: 'Categories',
                              actionLabel: 'View All (${categories.length})',
                              onAction: () => _showCategoriesModal(context),
                              isDark: isDark,
                            ),
                            _buildCategoriesSection(
                              context,
                              categories,
                              isDark,
                              primaryColor,
                            ),

                            SizedBox(height: context.isDesktop ? 32 : 20),

                            // 2. Best Sellers Section (4-column responsive grid)
                            _buildSectionHeader(
                              context,
                              title: 'Best Sellers',
                              actionLabel: 'View All',
                              onAction:
                                  bestSellersAreCabinets &&
                                      cabinetCategory != null
                                  ? () => _pushHomeRoute(
                                      context,
                                      ProductListingScreen(
                                        initialCategoryId: cabinetCategory.id,
                                        initialCategoryName:
                                            cabinetCategory.name,
                                      ),
                                      useRootNavigator: false,
                                    )
                                  : () => context.go('/products'),
                              isDark: isDark,
                            ),
                            if (bestSellersAreCabinets)
                              _buildBestSellersCarousel(context, bestSellers)
                            else
                              _buildResponsiveProductGrid(
                                context,
                                bestSellers,
                                sectionKey: 'best_sellers',
                                emptyMessage: 'Best seller products will appear here soon.',
                                maxItems: 4,
                              ),

                            // 3. Full-Width Middle Promotional Banner (Immediately below Best Sellers)
                            _buildFullWidthMiddlePromoBanner(context, isDark),

                            SizedBox(height: context.isDesktop ? 28 : 18),

                            // 4. New Arrivals 2026 (4-column responsive grid)
                            _buildSectionHeader(
                              context,
                              title: 'New Arrivals 2026',
                              actionLabel: 'View All',
                              onAction: () => context.go('/products'),
                              isDark: isDark,
                            ),
                            _buildResponsiveProductGrid(
                              context,
                              newArrivals,
                              sectionKey: 'new_arrivals',
                              emptyMessage:
                                  'New arrivals will appear here soon.',
                              maxItems: 4,
                            ),

                            SizedBox(height: context.isDesktop ? 32 : 20),

                            // 5. Featured Wholesale Deals (4-column responsive grid)
                            _buildSectionHeader(
                              context,
                              title: 'Featured Wholesale Deals',
                              actionLabel: 'View All',
                              onAction: () => context.go('/products'),
                              isDark: isDark,
                            ),
                            _buildResponsiveProductGrid(
                              context,
                              featuredProducts.isNotEmpty
                                  ? featuredProducts
                                  : wholesaleDeals,
                              sectionKey: 'featured_deals',
                              emptyMessage: 'No featured deals available yet.',
                              maxItems: 4,
                            ),

                            SizedBox(height: context.isDesktop ? 48 : 28),

                            // 6. Why Choose NeeroPlus? (feature highlights)
                            const WhyChooseSection(),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(height: context.isDesktop ? 56 : 36),
                    // Site footer (full width).
                    HomeFooter(
                      categories: categories,
                      onNavigate: (path) => context.go(path),
                      onCategoryTap: (cat) => _pushHomeRoute(
                        context,
                        ProductListingScreen(
                          initialCategoryId: cat.id,
                          initialCategoryName: cat.name,
                        ),
                        useRootNavigator: false,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 1. App Header (Mobile Only - on Desktop Web the sticky top navigation bar is used)
  Widget _buildHeader(BuildContext context) {
    if (context.isDesktop) {
      return const SizedBox.shrink();
    }

    // Mobile & Tablet Header with Uncropped Brand Logo
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1686C8).withValues(alpha: 0.09),
              blurRadius: 18,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFFFFFFFF),
                      Color(0xFFF0FAFF),
                      Color(0xFFCBEAFF),
                    ],
                    stops: [0, 0.44, 1],
                  ),
                ),
              ),
              const IgnorePointer(
                child: CustomPaint(painter: _HomeHeaderWavePainter()),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: BrandLogo(
                          width: 160,
                          height: 52,
                          fit: BoxFit.contain,
                          alignment: Alignment.centerLeft,
                        ),
                      ),
                    ),
                    _buildHeaderIconButton(
                      icon: Icons.person_outline_rounded,
                      tooltip: 'Profile',
                      onTap: () => context.go('/profile'),
                    ),
                    const SizedBox(width: 10),
                    _buildHeaderIconButton(
                      icon: Icons.shopping_cart_outlined,
                      badgeCount: ref.watch(cartProvider).totalItemCount,
                      tooltip: 'Shopping Cart',
                      onTap: () => _showCartDrawerModal(context),
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

  Widget _buildHeaderIconButton({
    required IconData icon,
    int badgeCount = 0,
    required String tooltip,
    required VoidCallback onTap,
    bool onDarkHeader = false,
  }) {
    return Material(
      color: onDarkHeader
          ? Colors.white.withValues(alpha: 0.14)
          : Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF203A5A)
          : const Color(0xFFF0F5FC),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () {
          debugPrint('>>> [HEADER BUTTON CLICKED] $tooltip <<<');
          onTap();
        },
        borderRadius: BorderRadius.circular(14),
        splashColor: Colors.white.withValues(alpha: 0.2),
        highlightColor: Colors.white.withValues(alpha: 0.08),
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: onDarkHeader
                  ? Colors.white24
                  : Theme.of(context).brightness == Brightness.dark
                  ? Colors.white12
                  : const Color(0xFFE1EAF5),
            ),
            boxShadow: onDarkHeader
                ? null
                : [
                    BoxShadow(
                      color: const Color(0xFF2A7BAB).withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                icon,
                size: 22,
                color: onDarkHeader
                    ? Colors.white
                    : Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : const Color(0xFF31577F),
              ),
              if (badgeCount > 0)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF3D57),
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      '$badgeCount',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // 3. Three-Line Menu: Categories Modal Sheet
  void _showCategoriesModal(BuildContext context) {
    final categories = ref.read(categoriesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (sheetContext, scrollController) {
            return Column(
              children: [
                // Modal Handle Bar & Title
                Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _homeBlue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.grid_view_rounded,
                              color: _homeBlue,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Wholesale Categories',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(modalContext),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Category Items List
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: categories.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final cat = categories[index];
                      return Material(
                        color: isDark
                            ? const Color(0xFF1E293B)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            Navigator.pop(modalContext);
                            _pushHomeRoute(
                              context,
                              ProductListingScreen(
                                initialCategoryId: cat.id,
                                initialCategoryName: cat.name,
                              ),
                              useRootNavigator: false,
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.grey.withValues(alpha: 0.2),
                                    ),
                                  ),
                                  padding: const EdgeInsets.all(6),
                                  child: AppImage(
                                    cat.imagePath,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      Icons.water_drop_rounded,
                                      color: _homeBlue,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        cat.name,
                                        style: TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w800,
                                          color: isDark
                                              ? Colors.white
                                              : const Color(0xFF0F172A),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        cat.description,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _homeBlue.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${cat.productCount} Items',
                                    style: const TextStyle(
                                      color: _homeBlue,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  color: Colors.grey,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Top dashboard section: product search and the four quick actions.
  Widget _buildTopSection(BuildContext context, bool isDark) {
    final isDesktop = context.isDesktop;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        isDesktop ? 24 : 12,
        16,
        isDesktop ? 32 : 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HomeSearchBar(
            isDark: isDark,
            onOpenProduct: (product) =>
                _pushHomeRoute(context, ProductDetailsScreen(product: product)),
            onAddToCart: (product) => addProductToCart(context, ref, product),
            onOpenFilters: () => _openFilters(context),
          ),
          SizedBox(height: isDesktop ? 28 : 24),
          _buildQuickActions(context, isDark),
        ],
      ),
    );
  }

  /// Opens the catalogue filter sheet (shared with the product listing). If
  /// the dealer changes any filter, the filtered product listing opens.
  Future<void> _openFilters(BuildContext context) async {
    String signature(ProductFilterState s) => [
      s.selectedCategoryId,
      s.minPrice,
      s.maxPrice,
      s.inStockOnly,
      (s.selectedBrands.toList()..sort()).join(','),
      s.sortOption,
    ].join('|');

    final before = signature(ref.read(productFilterProvider));
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const FilterBottomSheet(),
    );
    if (!mounted || !context.mounted) return;
    if (signature(ref.read(productFilterProvider)) == before) return;
    _pushHomeRoute(
      context,
      const ProductListingScreen(),
      useRootNavigator: false,
    );
  }

  // Quick actions: 4 in a row on wide screens, a 2-column grid otherwise.
  Widget _buildQuickActions(BuildContext context, bool isDark) {
    const actions = [
      (Icons.bolt_rounded, 'Bulk Order', 'Buy in bulk', Color(0xFF2563EB)),
      (
        Icons.local_shipping_rounded,
        'Track Orders',
        'Delivery status',
        Color(0xFF059669),
      ),
      (
        Icons.receipt_long_rounded,
        'GST Invoice',
        'Download invoices',
        Color(0xFF7C3AED),
      ),
      (
        Icons.account_balance_wallet_rounded,
        'Credit Limit',
        'Available credit',
        Color(0xFFD97706),
      ),
    ];

    void handleActionTap(String label) {
      if (label == 'Track Orders' || label == 'GST Invoice') {
        context.go('/orders');
      } else if (label == 'Credit Limit') {
        context.go('/profile');
      } else {
        context.go('/products');
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 860 ? 4 : 2;
        // Phones: stacked card layout so text never gets squeezed.
        final compact = width < 560;
        final gap = columns == 4 ? 20.0 : (compact ? 12.0 : 16.0);

        final rows = <Widget>[];
        for (var i = 0; i < actions.length; i += columns) {
          if (i > 0) rows.add(SizedBox(height: gap));
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var j = i; j < i + columns; j++) ...[
                    if (j > i) SizedBox(width: gap),
                    Expanded(
                      child: QuickActionTile(
                        icon: actions[j].$1,
                        label: actions[j].$2,
                        subtitle: actions[j].$3,
                        color: actions[j].$4,
                        compact: compact,
                        isDark: isDark,
                        onTap: () => handleActionTap(actions[j].$2),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }
        return Column(children: rows);
      },
    );
  }

  // Section Header
  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    required String? actionLabel,
    required VoidCallback? onAction,
    required bool isDark,
  }) {
    final isDesktop = context.isDesktop;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, isDesktop ? 22 : 16, 16, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: isDesktop ? 20 : 16,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
          ),
          if (actionLabel != null && actionLabel.isNotEmpty)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: onAction,
                child: Text(
                  actionLabel.endsWith('→') ? actionLabel : '$actionLabel →',
                  style: TextStyle(
                    fontSize: isDesktop ? 14 : 12.5,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0284C7),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Maps a category id/name to its image URL on the app's server
  /// (served from assets/images/ by server.js at /images/<filename>).
  String? _getCategoryLocalImage(String categoryId, String categoryName) {
    final lower = ('$categoryId $categoryName').toLowerCase();
    if (lower.contains('sys') || lower.contains('purifier')) {
      return ApiClient.imageUrl('RO_System.png');
    } else if (lower.contains('mem')) {
      return ApiClient.imageUrl('membrane.webp');
    } else if (lower.contains('flt') ||
        lower.contains('filter') ||
        lower.contains('cartridge') ||
        lower.contains('carbon')) {
      return ApiClient.imageUrl('filter.jpg');
    } else if (lower.contains('pmp') ||
        lower.contains('pump') ||
        lower.contains('booster')) {
      return ApiClient.imageUrl('pumps.webp');
    } else if (lower.contains('pip') ||
        lower.contains('tube') ||
        lower.contains('tubing')) {
      return ApiClient.imageUrl('tubes.jpg');
    } else if (lower.contains('spare') ||
        lower.contains('valve') ||
        lower.contains('part') ||
        lower.contains('smps')) {
      return ApiClient.imageUrl('spare_parts.jpg');
    }
    return null;
  }

  (IconData, Color, LinearGradient) _getCategoryVisuals(
    String categoryId,
    String categoryName,
  ) {
    final lower = ('$categoryId $categoryName').toLowerCase();
    if (lower.contains('sys') || lower.contains('purifier')) {
      return (
        Icons.kitchen_rounded,
        const Color(0xFF0284C7),
        const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE0F2FE), Color(0xFFBAE6FD)],
        ),
      );
    } else if (lower.contains('mem')) {
      return (
        Icons.layers_rounded,
        const Color(0xFF7C3AED),
        const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF3E8FF), Color(0xFFDDD6FE)],
        ),
      );
    } else if (lower.contains('flt') || lower.contains('filter')) {
      return (
        Icons.filter_alt_rounded,
        const Color(0xFF059669),
        const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFDCFCE7), Color(0xFFBBF7D0)],
        ),
      );
    } else if (lower.contains('pmp') || lower.contains('pump')) {
      return (
        Icons.speed_rounded,
        const Color(0xFFD97706),
        const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFEF3C7), Color(0xFFFDE68A)],
        ),
      );
    } else if (lower.contains('pip') || lower.contains('tube')) {
      return (
        Icons.alt_route_rounded,
        const Color(0xFF0284C7),
        const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE0F2FE), Color(0xFFCFFAFE)],
        ),
      );
    } else {
      return (
        Icons.settings_suggest_rounded,
        const Color(0xFF4F46E5),
        const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEEF2FF), Color(0xFFE0E7FF)],
        ),
      );
    }
  }

  Widget _buildCategoriesSection(
    BuildContext context,
    List<CategoryModel> categories,
    bool isDark,
    Color primaryColor,
  ) {
    if (categories.isEmpty) return const SizedBox.shrink();
    final isDesktop = context.isDesktop;
    final isTablet = context.isTablet;

    if (isDesktop) {
      // Desktop: All categories in a single row, evenly distributed with large image cards
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: categories.map((category) {
            final visuals = _getCategoryVisuals(category.id, category.name);
            final localImage = _getCategoryLocalImage(
              category.id,
              category.name,
            );
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: _buildCategoryImageCard(
                  context,
                  category: category,
                  localImagePath: localImage,
                  fallbackIcon: visuals.$1,
                  iconColor: visuals.$2,
                  gradient: visuals.$3,
                  isDark: isDark,
                  isDesktop: true,
                ),
              ),
            );
          }).toList(),
        ),
      );
    }

    if (isTablet) {
      // Tablet: 2 rows of 3 large image cards
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final itemWidth = (constraints.maxWidth - 24) / 3;
            return Wrap(
              spacing: 12,
              runSpacing: 14,
              children: categories.map((category) {
                final visuals = _getCategoryVisuals(category.id, category.name);
                final localImage = _getCategoryLocalImage(
                  category.id,
                  category.name,
                );
                return SizedBox(
                  width: itemWidth,
                  child: _buildCategoryImageCard(
                    context,
                    category: category,
                    localImagePath: localImage,
                    fallbackIcon: visuals.$1,
                    iconColor: visuals.$2,
                    gradient: visuals.$3,
                    isDark: isDark,
                    isDesktop: false,
                  ),
                );
              }).toList(),
            );
          },
        ),
      );
    }

    // Mobile: Horizontal scroll with large image cards
    return SizedBox(
      height: 168,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final category = categories[index];
          final visuals = _getCategoryVisuals(category.id, category.name);
          final localImage = _getCategoryLocalImage(category.id, category.name);
          return Container(
            width: 136,
            margin: const EdgeInsets.only(right: 12),
            child: _buildCategoryImageCard(
              context,
              category: category,
              localImagePath: localImage,
              fallbackIcon: visuals.$1,
              iconColor: visuals.$2,
              gradient: visuals.$3,
              isDark: isDark,
              isDesktop: false,
            ),
          );
        },
      ),
    );
  }

  /// Large image-first category card with product photo, name label, and item count badge.
  Widget _buildCategoryImageCard(
    BuildContext context, {
    required CategoryModel category,
    required String? localImagePath,
    required IconData fallbackIcon,
    required Color iconColor,
    required LinearGradient gradient,
    required bool isDark,
    required bool isDesktop,
  }) {
    final double imageHeight = isDesktop ? 140 : 108;

    // Resolve display image: prefer mapped URL, then DB image path via AppImage, else null
    final String? networkImage = category.imagePath.isNotEmpty
        ? category.imagePath
        : null;

    Widget buildImage() {
      if (localImagePath != null) {
        // Product photos have white backgrounds: show them whole (no crop)
        // on a white panel inset within the tinted image area.
        return Padding(
          padding: const EdgeInsets.all(6),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: CategoryImage(
                  url: localImagePath,
                  fallback: _buildCategoryIconFallback(
                    fallbackIcon,
                    iconColor,
                    gradient,
                    isDesktop,
                  ),
                ),
              ),
            ),
          ),
        );
      }
      if (networkImage != null) {
        return AppImage(
          networkImage,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildCategoryIconFallback(
            fallbackIcon,
            iconColor,
            gradient,
            isDesktop,
          ),
        );
      }
      return _buildCategoryIconFallback(
        fallbackIcon,
        iconColor,
        gradient,
        isDesktop,
      );
    }

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        key: ValueKey('home-category-${category.id}'),
        onTap: () => _pushHomeRoute(
          context,
          ProductListingScreen(
            initialCategoryId: category.id,
            initialCategoryName: category.name,
          ),
          useRootNavigator: false,
        ),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF142436) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark ? Colors.white12 : const Color(0xFFE8EEF5),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F2850)
                    .withValues(alpha: isDark ? 0.22 : 0.07),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Image Section ──────────────────────────────────────
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(17),
                ),
                child: SizedBox(
                  height: imageHeight,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Gradient tinted background behind image
                      DecoratedBox(
                        decoration: BoxDecoration(gradient: gradient),
                      ),
                      // Product image
                      buildImage(),
                      // Subtle bottom-to-top scrim so text reads cleanly
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 36,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.28),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Item-count badge (top-right)
                      if (category.productCount > 0)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${category.productCount} Items',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // ── Label Section ──────────────────────────────────────
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isDesktop ? 12 : 8,
                  vertical: isDesktop ? 12 : 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        category.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: isDesktop ? 13.5 : 11.5,
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF0F2850),
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: isDesktop ? 18 : 15,
                      color: iconColor,
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

  Widget _buildCategoryIconFallback(
    IconData icon,
    Color iconColor,
    LinearGradient gradient,
    bool isDesktop,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: gradient),
      child: Center(
        child: Icon(icon, size: isDesktop ? 48 : 36, color: iconColor),
      ),
    );
  }

  Widget _buildCategoryCard(
    BuildContext context, {
    required CategoryModel category,
    required IconData icon,
    required Color iconColor,
    required LinearGradient gradient,
    required bool isDark,
    required bool isDesktop,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('home-category-${category.id}'),
        onTap: () => _pushHomeRoute(
          context,
          ProductListingScreen(
            initialCategoryId: category.id,
            initialCategoryName: category.name,
          ),
          useRootNavigator: false,
        ),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 10 : 6,
            vertical: isDesktop ? 14 : 10,
          ),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF142436) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F2850)
                    .withValues(alpha: isDark ? 0.2 : 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: isDesktop ? 62 : 46,
                height: isDesktop ? 62 : 46,
                decoration: BoxDecoration(
                  gradient: gradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: iconColor.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    icon,
                    size: isDesktop ? 30 : 22,
                    color: iconColor,
                  ),
                ),
              ),
              SizedBox(height: isDesktop ? 10 : 6),
              Text(
                category.name,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: isDesktop ? 13 : 11,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0F2850),
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Full-Width Middle Promotional Banner (Right below Best Sellers)
  Widget _buildFullWidthMiddlePromoBanner(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 26, 16, 10),
      child: WholesalePromoBanner(
        isDesktop: context.isDesktop,
        onExplore: () => context.go('/products'),
      ),
    );
  }

  // Responsive 4-Column Product Grid (Desktop: 4, Tablet: 3, Mobile: 2)
  /// Best Sellers slider: 4 Cabinet cards across on desktop (3 on tablet,
  /// 2 on phone); the rest by swiping, mouse drag or the arrows.
  Widget _buildBestSellersCarousel(
    BuildContext context,
    List<ProductModel> products,
  ) {
    final isDesktop = context.isDesktop;
    final isTablet = context.isTablet;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: HomeProductCarousel(
        products: products,
        sectionKey: 'best_sellers',
        visibleCount: isDesktop
            ? homeBestSellerVisibleDesktop
            : (isTablet
                  ? homeBestSellerVisibleTablet
                  : homeBestSellerVisiblePhone),
        spacing: isDesktop ? 20.0 : (isTablet ? 14.0 : 12.0),
        onTap: (product, heroTag) => _pushHomeRoute(
          context,
          ProductDetailsScreen(product: product, heroTag: heroTag),
        ),
        onAddToCart: (product) => addProductToCart(context, ref, product),
      ),
    );
  }

  Widget _buildResponsiveProductGrid(
    BuildContext context,
    List<ProductModel> products, {
    required String sectionKey,
    required String emptyMessage,
    int maxItems = 4,
  }) {
    if (products.isEmpty) {
      return Container(
        height: 86,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
          ),
        ),
        child: Text(
          emptyMessage,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }

    final isDesktop = context.isDesktop;
    final isTablet = context.isTablet;

    final crossAxisCount = isDesktop ? 4 : (isTablet ? 3 : 2);
    final spacing = isDesktop ? 20.0 : (isTablet ? 14.0 : 12.0);
    final displayProducts = products.take(maxItems).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardWidth =
              (constraints.maxWidth - spacing * (crossAxisCount - 1)) /
              crossAxisCount;
          return GridView.builder(
            key: ValueKey('home-grid-$sectionKey'),
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            itemCount: displayProducts.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: spacing,
              mainAxisSpacing: spacing,
              // Content-sized height: no empty gap inside the card.
              mainAxisExtent: HomeProductCard.extentFor(cardWidth),
            ),
            itemBuilder: (context, index) {
              final product = displayProducts[index];
              final heroTag = 'home_${sectionKey}_${product.id}_$index';
              return HomeProductCard(
                product: product,
                heroTag: heroTag,
                onTap: () => _pushHomeRoute(
                  context,
                  ProductDetailsScreen(product: product, heroTag: heroTag),
                ),
                onAddToCart: () => addProductToCart(context, ref, product),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildCatalogError(Object? error) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.error.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.wifi_off_rounded,
            size: 32,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 10),
          Text(
            'We couldn’t load the product catalog',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            '$error',
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => ref.invalidate(catalogProductsProvider),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }

  // Skeleton Loader for Dashboard
  Widget _buildSkeletonDashboard() {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          LoadingSkeleton.rectangular(
            width: double.infinity,
            height: 150,
            borderRadius: 20,
          ),
          SizedBox(height: 16),
          LoadingSkeleton.rectangular(
            width: double.infinity,
            height: 180,
            borderRadius: 16,
          ),
        ],
      ),
    );
  }

  void _showCartDrawerModal(BuildContext context) {
    context.go('/cart');
  }
}
