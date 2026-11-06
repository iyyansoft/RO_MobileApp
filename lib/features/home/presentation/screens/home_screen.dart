import 'dart:async';

import '../../../products/presentation/widgets/cart_actions.dart';
import '../../../../core/widgets/app_image.dart';
import '../../../../core/widgets/category_image.dart';
import '../widgets/animated_banner_background.dart';
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
  // Infinite carousel virtual index starting at 6001 so that banner 1 (Commercial RO Plants)
  // is centered by default, banner 0 (Carbon Filters) is on left, banner 2 (Membranes) is on right.
  int _virtualIndex = 6001;
  PageController? _bannerPageController;
  int? _lastLayoutMode;
  final ScrollController _scrollController = ScrollController();
  Timer? _bannerTimer;

  void _initBannerController(bool isDesktop, bool isTablet) {
    final mode = isDesktop ? 2 : (isTablet ? 1 : 0);
    if (_bannerPageController != null && _lastLayoutMode == mode) return;
    _lastLayoutMode = mode;
    _bannerPageController?.dispose();
    // Desktop: 0.44 displays one prominent center banner with left and right banners partially visible.
    // Tablet: 0.72 displays centered banner with subtle peek.
    // Mobile: 1.0 displays exactly one complete banner at a time with swipe support.
    final fraction = isDesktop ? 0.44 : (isTablet ? 0.72 : 1.0);
    _bannerPageController = PageController(
      initialPage: _virtualIndex,
      viewportFraction: fraction,
    );
  }

  @override
  void initState() {
    super.initState();
    _scheduleBannerAdvance();
  }

  void _scheduleBannerAdvance() {
    _bannerTimer?.cancel();
    _bannerTimer = Timer(const Duration(milliseconds: 4500), () {
      if (!mounted ||
          _bannerPageController == null ||
          !_bannerPageController!.hasClients) {
        _scheduleBannerAdvance();
        return;
      }
      _virtualIndex++;
      _bannerPageController!.animateToPage(
        _virtualIndex,
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _bannerPageController?.dispose();
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
    final bestSellers = allProducts
        .where((p) => p.discountPercentage >= 30)
        .toList();
    final newArrivals = allProducts.reversed.toList();
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

                          if (catalog.isLoading)
                            _buildSkeletonDashboard()
                          else if (catalog.hasError)
                            _buildCatalogError(catalog.error)
                          else ...[
                            _buildSearchBar(context, isDark, primaryColor),

                            _buildQuickActions(context, isDark),

                            _buildBannerCarousel(context, isDark),

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
                              onAction: () => context.go('/products'),
                              isDark: isDark,
                            ),
                            _buildResponsiveProductGrid(
                              context,
                              bestSellers.isNotEmpty
                                  ? bestSellers
                                  : allProducts,
                              sectionKey: 'best_sellers',
                              emptyMessage:
                                  'Best seller products will appear here soon.',
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

  Widget _buildSearchBar(
    BuildContext context,
    bool isDark,
    Color primaryColor,
  ) {
    final isDesktop = context.isDesktop;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: isDesktop ? 14 : 8,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isDesktop ? 1100 : double.infinity,
          ),
          child: Material(
            color: isDark ? AppColors.surfaceDark : Colors.white,
            borderRadius: BorderRadius.circular(32),
            child: InkWell(
              onTap: () => _openSearchModal(context),
              borderRadius: BorderRadius.circular(32),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF1E2D3D)
                        : const Color(0xFFE2E8F0),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F2850)
                          .withValues(alpha: isDark ? 0.2 : 0.04),
                      blurRadius: 14,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.search_rounded,
                      color: Color(0xFF64748B),
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Search RO systems, membranes, pumps, spares...',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF94A3B8),
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F2544),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.tune_rounded,
                        color: Colors.white,
                        size: 19,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 3. Quick Actions Row (4 Aligned Cards)
  Widget _buildQuickActions(BuildContext context, bool isDark) {
    final isDesktop = context.isDesktop;
    final actions = [
      {
        'icon': Icons.bolt_rounded,
        'label': 'Bulk Order',
        'subtitle': 'Buy in bulk',
        'color': const Color(0xFF2563EB),
      },
      {
        'icon': Icons.local_shipping_rounded,
        'label': 'Track Orders',
        'subtitle': 'Delivery status',
        'color': const Color(0xFF059669),
      },
      {
        'icon': Icons.receipt_long_rounded,
        'label': 'GST Invoice',
        'subtitle': 'Download invoices',
        'color': const Color(0xFF7C3AED),
      },
      {
        'icon': Icons.account_balance_wallet_rounded,
        'label': 'Credit Limit',
        'subtitle': 'Available credit',
        'color': const Color(0xFFD97706),
      },
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

    Widget buildCard(Map<String, dynamic> act, {bool isMobileCompact = false}) {
      final label = act['label'] as String;
      return QuickActionTile(
        icon: act['icon'] as IconData,
        label: label,
        subtitle: act['subtitle'] as String,
        color: act['color'] as Color,
        compact: isMobileCompact,
        isDark: isDark,
        onTap: () => handleActionTap(label),
      );
    }

    if (isDesktop) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Row(
              children: actions.map((act) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: buildCard(act),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      );
    }

    // Tablet & Mobile
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 560) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: actions.map((act) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: buildCard(act, isMobileCompact: true),
                  ),
                );
              }).toList(),
            ),
          );
        }

        // Narrow Mobile: 2x2 grid
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: buildCard(actions[0], isMobileCompact: true)),
                  const SizedBox(width: 8),
                  Expanded(child: buildCard(actions[1], isMobileCompact: true)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: buildCard(actions[2], isMobileCompact: true)),
                  const SizedBox(width: 8),
                  Expanded(child: buildCard(actions[3], isMobileCompact: true)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // 4. Exactly 6 Unique Promotional Banners Infinite Carousel
  Widget _buildBannerCarousel(BuildContext context, bool isDark) {
    final isDesktop = context.isDesktop;
    final isTablet = context.isTablet;
    _initBannerController(isDesktop, isTablet);

    final carouselHeight = isDesktop ? 256.0 : (isTablet ? 214.0 : 196.0);

    return Column(
      children: [
        SizedBox(
          height: carouselHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              PageView.builder(
                controller: _bannerPageController,
                itemCount: null,
                onPageChanged: (idx) {
                  setState(() {
                    _virtualIndex = idx;
                  });
                  _scheduleBannerAdvance();
                },
                itemBuilder: (context, idx) {
                  final bannerIndex = idx % 6;
                  return AnimatedBuilder(
                    animation: _bannerPageController!,
                    builder: (context, child) {
                      double currentPosition = idx.toDouble();
                      if (_bannerPageController!.hasClients &&
                          _bannerPageController!.position.haveDimensions) {
                        currentPosition =
                            _bannerPageController!.page ?? idx.toDouble();
                      }
                      final diff = (currentPosition - idx).abs();
                      final scale = isDesktop
                          ? (1.0 - (diff * 0.12).clamp(0.0, 0.12))
                          : (isTablet
                                ? (1.0 - (diff * 0.08).clamp(0.0, 0.08))
                                : 1.0);
                      final opacity = isDesktop
                          ? (1.0 - (diff * 0.15).clamp(0.0, 0.15))
                          : 1.0;

                      return Transform.scale(
                        scale: scale,
                        alignment: Alignment.center,
                        child: Opacity(opacity: opacity, child: child),
                      );
                    },
                    child: _buildCarouselBannerItem(
                      context,
                      bannerIndex,
                      isDark,
                      isDesktop,
                    ),
                  );
                },
              ),
              // Floating Navigation Arrows (Desktop & Tablet)
              if (isDesktop || isTablet) ...[
                Positioned(
                  left: isDesktop ? 8 : 4,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _buildCarouselArrow(
                      icon: Icons.chevron_left_rounded,
                      onTap: () {
                        if (_bannerPageController != null &&
                            _bannerPageController!.hasClients) {
                          _virtualIndex--;
                          _bannerPageController!.animateToPage(
                            _virtualIndex,
                            duration: const Duration(milliseconds: 550),
                            curve: Curves.easeInOutCubic,
                          );
                        }
                      },
                    ),
                  ),
                ),
                Positioned(
                  right: isDesktop ? 8 : 4,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _buildCarouselArrow(
                      icon: Icons.chevron_right_rounded,
                      onTap: () {
                        if (_bannerPageController != null &&
                            _bannerPageController!.hasClients) {
                          _virtualIndex++;
                          _bannerPageController!.animateToPage(
                            _virtualIndex,
                            duration: const Duration(milliseconds: 550),
                            curve: Curves.easeInOutCubic,
                          );
                        }
                      },
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 6 Pagination Dots
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(6, (idx) {
            final isActive = (_virtualIndex % 6) == idx;
            return GestureDetector(
              onTap: () {
                if (_bannerPageController != null &&
                    _bannerPageController!.hasClients) {
                  final currentDot = _virtualIndex % 6;
                  var diff = idx - currentDot;
                  if (diff > 3) diff -= 6;
                  if (diff < -3) diff += 6;
                  _virtualIndex += diff;
                  _bannerPageController!.animateToPage(
                    _virtualIndex,
                    duration: const Duration(milliseconds: 550),
                    curve: Curves.easeInOutCubic,
                  );
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                margin: const EdgeInsets.symmetric(horizontal: 3.5),
                width: isActive ? 22 : 6.5,
                height: 6.5,
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0xFF0077D4)
                      : (isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
                  borderRadius: BorderRadius.circular(3.5),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildCarouselArrow({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      shadowColor: const Color(0x28000000),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          child: Icon(icon, size: 22, color: const Color(0xFF334155)),
        ),
      ),
    );
  }

  Widget _buildBannerButton({
    required String label,
    required Color color,
    required VoidCallback onTap,
    Color textColor = Colors.white,
    bool isSmall = false,
  }) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isSmall ? 14 : 20,
            vertical: isSmall ? 7 : 10,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.32),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: isSmall ? 11 : 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBannerBadge({
    required String text,
    required Color bgColor,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildCarouselCardContainer({
    required Widget child,
    required LinearGradient gradient,
    required Color accentColor,
    required bool isDark,
    required bool isDesktop,
  }) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: isDesktop ? 8 : 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.white.withValues(alpha: 0.85),
          width: 1.4,
        ),
        boxShadow: [
          // Soft coloured glow + a tight contact shadow for depth.
          BoxShadow(
            color: accentColor.withValues(alpha: isDark ? 0.25 : 0.22),
            blurRadius: 26,
            spreadRadius: -4,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: const Color(0xFF0F2850)
                .withValues(alpha: isDark ? 0.3 : 0.07),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(21),
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedBannerBackground(
              gradient: gradient,
              accentColor: accentColor,
              isDark: isDark,
            ),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildPurifierFeaturePills(bool isDesktop) {
    final pills = [
      (Icons.water_drop_rounded, 'Multi-Stage'),
      (Icons.shield_rounded, 'RO + UV'),
      (Icons.eco_rounded, 'Mineral'),
      (Icons.handyman_rounded, 'Low Maint.'),
    ];
    return Wrap(
      spacing: isDesktop ? 6 : 4,
      runSpacing: 4,
      children: pills.map((p) {
        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 6 : 4,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFBAE6FD), width: 0.8),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0284C7).withValues(alpha: 0.06),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                p.$1,
                size: isDesktop ? 10.5 : 8.5,
                color: const Color(0xFF0284C7),
              ),
              const SizedBox(width: 3),
              Text(
                p.$2,
                style: TextStyle(
                  fontSize: isDesktop ? 8.5 : 7.5,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF0369A1),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCarouselCardContent({
    required Widget badge,
    required String title,
    required String description,
    required String buttonLabel,
    required Color buttonColor,
    required Color titleColor,
    required Color descriptionColor,
    required String imageAsset,
    required VoidCallback onButtonTap,
    required bool isDesktop,
    Color? buttonTextColor,
    Widget? featurePills,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isDesktop ? 30 : 16,
        isDesktop ? 18 : 12,
        isDesktop ? 18 : 12,
        isDesktop ? 18 : 12,
      ),
      child: Row(
        children: [
          // Copy. Keeps its full width so text wraps normally, and scales
          // down slightly (instead of overflowing) when a banner's content is
          // taller than the space available.
          Expanded(
            flex: 11,
            child: LayoutBuilder(
              builder: (context, copyBox) => FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: copyBox.maxWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      badge,
                      SizedBox(height: isDesktop ? 10 : 6),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: isDesktop ? 24 : 15.5,
                          fontWeight: FontWeight.w900,
                          color: titleColor,
                          height: 1.12,
                          letterSpacing: -0.4,
                        ),
                      ),
                      SizedBox(height: isDesktop ? 7 : 4),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: isDesktop ? 12.5 : 9.5,
                          color: descriptionColor,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (featurePills != null) ...[
                        SizedBox(height: isDesktop ? 8 : 4),
                        featurePills,
                      ],
                      SizedBox(height: isDesktop ? 14 : 8),
                      _buildBannerButton(
                        label: buttonLabel,
                        color: buttonColor,
                        textColor: buttonTextColor ?? Colors.white,
                        onTap: onButtonTap,
                        isSmall: !isDesktop,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: isDesktop ? 16 : 10),
          // Product showcase: transparent cut-out, shown whole (never
          // cropped or stretched) directly on the banner background.
          Expanded(
            flex: 9,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: isDesktop ? 10 : 8),
              child: FloatingBannerProduct(
                child: Image.asset(
                  imageAsset,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.water_drop_rounded,
                    size: 55,
                    color: Color(0xFF0284C7),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCarouselBannerItem(
    BuildContext context,
    int index,
    bool isDark,
    bool isDesktop,
  ) {
    switch (index) {
      case 0:
        // 1. Genuine RO Spares (Left banner in reference image)
        return _buildCarouselCardContainer(
          isDark: isDark,
          isDesktop: isDesktop,
          accentColor: const Color(0xFF0284C7),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF9CCEF5), Color(0xFFC3E2FA), Color(0xFFE8F4FE)],
          ),
          child: _buildCarouselCardContent(
            badge: _buildBannerBadge(
              text: '100% GENUINE',
              bgColor: const Color(0xFFE0F2FE),
              textColor: const Color(0xFF0284C7),
            ),
            title: 'Genuine\nRO Spares',
            description: 'Filters | Membranes |\nPumps | Accessories',
            buttonLabel: 'Shop Now  →',
            buttonColor: const Color(0xFF0284C7),
            titleColor: const Color(0xFF0F2850),
            descriptionColor: const Color(0xFF0369A1),
            imageAsset: 'assets/images/banners_cutout/spare_parts.png',
            onButtonTap: () => context.go('/products'),
            isDesktop: isDesktop,
          ),
        );

      case 1:
        // 2. Neero+ RO Water Purifiers (Center flagship banner in reference image)
        return _buildCarouselCardContainer(
          isDark: isDark,
          isDesktop: isDesktop,
          accentColor: const Color(0xFF0284C7),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF94C8F4), Color(0xFFBEDDF9), Color(0xFFE6F2FE)],
          ),
          child: _buildCarouselCardContent(
            badge: _buildBannerBadge(
              text: 'BEST SELLER',
              bgColor: const Color(0xFF0284C7),
              textColor: Colors.white,
            ),
            title: 'Neero+ RO\nWater Purifiers',
            description: 'Pure • Safe • Healthy Drinking Water',
            buttonLabel: 'Shop Now  →',
            buttonColor: const Color(0xFF0284C7),
            titleColor: const Color(0xFF0F2850),
            descriptionColor: const Color(0xFF0369A1),
            imageAsset: 'assets/images/banners_cutout/ro_system.png',
            featurePills: _buildPurifierFeaturePills(isDesktop),
            onButtonTap: () => context.go('/products'),
            isDesktop: isDesktop,
          ),
        );

      case 2:
        // 3. RO Pipes, Tubing & Fittings
        return _buildCarouselCardContainer(
          isDark: isDark,
          isDesktop: isDesktop,
          accentColor: const Color(0xFF0284C7),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF9DD0F2), Color(0xFFC0E3F6), Color(0xFFD9F3E8)],
          ),
          child: _buildCarouselCardContent(
            badge: _buildBannerBadge(
              text: 'INSTALL ESSENTIALS',
              bgColor: const Color(0xFF0284C7),
              textColor: Colors.white,
            ),
            title: 'RO Pipes, Tubing\n& Fittings',
            description:
                'Tubing, Connectors & Accessories\nfor Every RO Installation',
            buttonLabel: 'Shop Fittings  →',
            buttonColor: const Color(0xFF0284C7),
            titleColor: const Color(0xFF0F2850),
            descriptionColor: const Color(0xFF0369A1),
            imageAsset: 'assets/images/banners_cutout/tubes.png',
            onButtonTap: () => context.go('/products'),
            isDesktop: isDesktop,
          ),
        );

      case 3:
        // 4. Premium Filter Membranes
        return _buildCarouselCardContainer(
          isDark: isDark,
          isDesktop: isDesktop,
          accentColor: const Color(0xFF8B5CF6),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFC9AEF8), Color(0xFFDCCBFB), Color(0xFFF1E9FE)],
          ),
          child: _buildCarouselCardContent(
            badge: _buildBannerBadge(
              text: '98% TDS REJECTION',
              bgColor: const Color(0xFF8B5CF6),
              textColor: Colors.white,
            ),
            title: 'Premium Filter\nMembranes',
            description: 'High TDS Rejection 75 GPD &\n100 GPD Vented Anti-Bacterial Sheets',
            buttonLabel: 'Order Spares  →',
            buttonColor: const Color(0xFF7C3AED),
            titleColor: const Color(0xFF3B0764),
            descriptionColor: const Color(0xFF581C87),
            imageAsset: 'assets/images/banners_cutout/membrane.png',
            onButtonTap: () => context.go('/products'),
            isDesktop: isDesktop,
          ),
        );

      case 4:
        // 5. High Pressure RO Booster Pumps
        return _buildCarouselCardContainer(
          isDark: isDark,
          isDesktop: isDesktop,
          accentColor: const Color(0xFF06B6D4),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF8BDDEC), Color(0xFFB6EAF3), Color(0xFFDDF7FB)],
          ),
          child: _buildCarouselCardContent(
            badge: _buildBannerBadge(
              text: 'HEAVY DUTY',
              bgColor: const Color(0xFF06B6D4),
              textColor: Colors.white,
            ),
            title: 'High Pressure\nRO Booster Pumps',
            description: '100 GPD to 450 GPD Heavy-Duty Motors\n100% Pure Copper Windings',
            buttonLabel: 'Explore Range  →',
            buttonColor: const Color(0xFF0891B2),
            titleColor: const Color(0xFF0E4C56),
            descriptionColor: const Color(0xFF155E75),
            imageAsset: 'assets/images/banners_cutout/pumps.png',
            onButtonTap: () => context.go('/products'),
            isDesktop: isDesktop,
          ),
        );

      case 5:
      default:
        // 6. Activated Carbon Filters
        return _buildCarouselCardContainer(
          isDark: isDark,
          isDesktop: isDesktop,
          accentColor: const Color(0xFF10B981),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF98E2B8), Color(0xFFC0EED3), Color(0xFFE2F8EB)],
          ),
          child: _buildCarouselCardContent(
            badge: _buildBannerBadge(
              text: 'LONG LASTING',
              bgColor: const Color(0xFFD1FAE5),
              textColor: const Color(0xFF059669),
            ),
            title: 'Activated\nCarbon Filters',
            description: 'Remove Chlorine, Odour\n& Organic Impurities',
            buttonLabel: 'Shop Now  →',
            buttonColor: const Color(0xFF10B981),
            titleColor: const Color(0xFF064E3B),
            descriptionColor: const Color(0xFF166534),
            imageAsset: 'assets/images/banners_cutout/filter.png',
            onButtonTap: () => context.go('/products'),
            isDesktop: isDesktop,
          ),
        );
    }
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
            height: 48,
            borderRadius: 16,
          ),
          SizedBox(height: 16),
          LoadingSkeleton.rectangular(
            width: double.infinity,
            height: 70,
            borderRadius: 16,
          ),
          SizedBox(height: 16),
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

  void _openSearchModal(BuildContext context) {
    debugPrint("HEADER SEARCH BUTTON TAPPED");
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) => const _SearchModalWidget(),
    );
  }
}

// FRESH REBUILT DEDICATED SEARCH UI MODAL
class _SearchModalWidget extends ConsumerStatefulWidget {
  const _SearchModalWidget();

  @override
  ConsumerState<_SearchModalWidget> createState() => _SearchModalWidgetState();
}

class _SearchModalWidgetState extends ConsumerState<_SearchModalWidget> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  // Singular & Plural Aware Case-Insensitive Category & Product Search Matching
  bool _matchSearchQuery(ProductModel product, String query) {
    final raw = query.trim().toLowerCase();
    if (raw.isEmpty) return false;

    // Normalize multiple whitespace
    final q = raw.replaceAll(RegExp(r'\s+'), ' ');

    final catId = product.categoryId.toLowerCase();
    final catName = product.categoryName.toLowerCase();
    final prodName = product.name.toLowerCase();
    final brandName = product.brand.toLowerCase();
    final skuName = product.sku.toLowerCase();
    final descName = product.description.toLowerCase();

    // 1. Requirement 6: Explicit Category Keyword Search Mappings
    final isFilterQuery =
        q == 'filter' || q == 'filters' || q.startsWith('filter');
    final isPumpQuery =
        q == 'pump' ||
        q == 'pumps' ||
        q.startsWith('pump') ||
        q.contains('booster');
    final isMembraneQuery =
        q == 'membrane' || q == 'membranes' || q.startsWith('membrane');
    final isPipeQuery = q == 'pipe' || q == 'pipes' || q.contains('tubing');
    final isSpareQuery =
        q == 'spare' ||
        q == 'spares' ||
        q.contains('spare') ||
        q.contains('part');
    final isAccessoryQuery =
        q == 'accessory' || q == 'accessories' || q.contains('fitting');

    if (isFilterQuery &&
        (catId.contains('filter') ||
            catName.contains('filter') ||
            prodName.contains('filter'))) {
      return true;
    }
    if (isPumpQuery &&
        (catId.contains('pump') ||
            catName.contains('pump') ||
            prodName.contains('pump'))) {
      return true;
    }
    if (isMembraneQuery &&
        (catId.contains('membrane') ||
            catName.contains('membrane') ||
            prodName.contains('membrane'))) {
      return true;
    }
    if (isPipeQuery &&
        (catId.contains('pipe') ||
            catName.contains('pipe') ||
            prodName.contains('pipe') ||
            prodName.contains('tubing'))) {
      return true;
    }
    if (isSpareQuery &&
        (catId.contains('spare') ||
            catName.contains('spare') ||
            catId.contains('part') ||
            catName.contains('part') ||
            prodName.contains('spare') ||
            prodName.contains('part') ||
            catId.contains('purifier_parts'))) {
      return true;
    }
    if (isAccessoryQuery &&
        (catId.contains('accessory') ||
            catName.contains('accessory') ||
            catId.contains('connector') ||
            catName.contains('connector'))) {
      return true;
    }

    // 2. Singular & Plural Tokens Matching
    final String singularQ = (q.endsWith('s') && q.length > 2)
        ? q.substring(0, q.length - 1)
        : q;
    final String pluralQ = q.endsWith('s') ? q : '${q}s';

    final List<String> matchTokens = [q, singularQ, pluralQ];

    final List<String> targetFields = [
      prodName,
      brandName,
      catName,
      catId,
      skuName,
      descName,
    ];

    for (final token in matchTokens) {
      if (token.isEmpty) continue;
      for (final field in targetFields) {
        if (field.contains(token)) return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allProducts = ref.watch(allProductsProvider);
    final query = _searchController.text.trim();
    final searchResults = allProducts
        .where((p) => _matchSearchQuery(p, query))
        .toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag Handle
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),

          // Header Row: < Back Button | Search TextField | Clear (X)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                // Back Button (Matched 46px height and 14px radius)
                Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1E293B)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF334155)
                              : const Color(0xFFE2E8F0),
                          width: 1.0,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.arrow_back_rounded,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF0F172A),
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Search TextField (Matched 46px height, 14px radius, subtle border & shadow)
                Expanded(
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF334155)
                            : const Color(0xFFE2E8F0),
                        width: 1.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? 0.2 : 0.04,
                          ),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      autofocus: true,
                      showCursor: true,
                      cursorColor: _homeBlue,
                      textAlignVertical: TextAlignVertical.center,
                      onChanged: (val) => setState(() {}),
                      style: TextStyle(
                        fontSize: 14.5,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Search products, parts, brands...',
                        hintStyle: const TextStyle(
                          fontSize: 13.5,
                          color: Color(0xFF94A3B8),
                          fontWeight: FontWeight.w400,
                        ),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: Color(0xFF94A3B8),
                          size: 20,
                        ),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(
                                  Icons.cancel_rounded,
                                  size: 18,
                                  color: Color(0xFF94A3B8),
                                ),
                                onPressed: () {
                                  setState(() {
                                    _searchController.clear();
                                  });
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),
          const Divider(height: 1),

          // Search Results or Empty State View
          Expanded(
            child: query.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 20,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.trending_up_rounded,
                              size: 18,
                              color: _homeBlue,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Trending Wholesale Searches',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF0F172A),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 10,
                          children:
                              [
                                'Filter',
                                'RO Pump',
                                'Membrane',
                                'Pipe',
                                'RO Spares',
                                '50 LPH System',
                                'SMPS Adapter',
                                'Float Valve',
                              ].map((tag) {
                                return Material(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                  child: InkWell(
                                    onTap: () {
                                      setState(() {
                                        _searchController.text = tag;
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? const Color(0xFF1E293B)
                                            : const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: isDark
                                              ? const Color(0xFF334155)
                                              : const Color(0xFFE2E8F0),
                                          width: 1.0,
                                        ),
                                      ),
                                      child: Text(
                                        tag,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: isDark
                                              ? Colors.white70
                                              : const Color(0xFF1E293B),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                        ),
                      ],
                    ),
                  )
                : searchResults.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.search_off_rounded,
                            size: 54,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No products found',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'No results match "$query". Try searching for "filter", "pump", "membrane", "pipe", or "spares".',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: searchResults.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final product = searchResults[index];
                      return Material(
                        color: isDark
                            ? const Color(0xFF1E293B)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            Navigator.pop(
                              context,
                            ); // Close search modal cleanly
                            _pushHomeRoute(
                              context,
                              ProductDetailsScreen(product: product),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.grey.withValues(alpha: 0.2),
                                    ),
                                  ),
                                  padding: const EdgeInsets.all(4),
                                  child: AppImage(
                                    product.displayImageUrl,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      Icons.water_drop_rounded,
                                      color: _homeBlue,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        product.brand.toUpperCase(),
                                        style: const TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w900,
                                          color: _homeBlue,
                                        ),
                                      ),
                                      Text(
                                        product.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w800,
                                          color: isDark
                                              ? Colors.white
                                              : const Color(0xFF0F172A),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Text(
                                            '₹${product.dealerPrice.toStringAsFixed(0)}',
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w900,
                                              color: _homeBlue,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'MOQ: ${product.moq}',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: const BoxDecoration(
                                      color: _homeBlue,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.add_rounded,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                  onPressed: () =>
                                      addProductToCart(context, ref, product),
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
      ),
    );
  }
}
