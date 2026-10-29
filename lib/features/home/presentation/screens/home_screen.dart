import 'dart:async';

import '../../../products/presentation/widgets/cart_actions.dart';
import '../../../../core/widgets/app_image.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/loading_skeleton.dart';
import '../../../cart/presentation/providers/cart_provider.dart';
import '../../../products/domain/models/category_model.dart';
import '../../../products/domain/models/product_model.dart';
import '../../../products/presentation/providers/product_provider.dart';
import '../../../products/presentation/screens/product_details_screen.dart';
import '../../../products/presentation/screens/product_listing_screen.dart';
import '../../../products/presentation/widgets/product_card.dart';

const _homeBlue = AppColors.primaryLight;
const _homeBlueBright = AppColors.accentDark;

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

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _activeBannerIndex = 0;
  final PageController _bannerPageController = PageController();
  final ScrollController _scrollController = ScrollController();
  Timer? _bannerTimer;

  @override
  void initState() {
    super.initState();
    _scheduleBannerAdvance();
  }

  void _scheduleBannerAdvance() {
    _bannerTimer?.cancel();
    _bannerTimer = Timer(const Duration(milliseconds: 3500), () {
      if (!mounted || !_bannerPageController.hasClients) {
        _scheduleBannerAdvance();
        return;
      }
      _bannerPageController.animateToPage(
        (_activeBannerIndex + 1) % 2,
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _bannerPageController.dispose();
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
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(catalogCategoriesProvider);
            ref.invalidate(catalogProductsProvider);
            await ref.read(catalogProductsProvider.future);
          },
          child: SingleChildScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 100),
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

                  _buildSectionHeader(
                    context,
                    title: 'Categories',
                    actionLabel: 'View All (${categories.length})',
                    onAction: () => _showCategoriesModal(context),
                    isDark: isDark,
                  ),
                  _buildCategoriesHorizontalList(
                    context,
                    categories,
                    isDark,
                    primaryColor,
                  ),

                  // 6. FEATURED WHOLESALE DEALS
                  _buildSectionHeader(
                    context,
                    title: 'Featured Wholesale Deals',
                    actionLabel: 'View All',
                    onAction: () => context.go('/products'),
                    isDark: isDark,
                  ),
                  _buildHorizontalProductList(
                    featuredProducts,
                    emptyMessage: 'No featured deals available yet.',
                    sectionKey: 'featured',
                  ),

                  // 7. BEST SELLERS SECTION
                  _buildSectionHeader(
                    context,
                    title: 'Best Sellers',
                    actionLabel: 'Explore',
                    onAction: () => context.go('/products'),
                    isDark: isDark,
                  ),
                  _buildHorizontalProductList(
                    bestSellers.isEmpty
                        ? allProducts.take(4).toList()
                        : bestSellers,
                    emptyMessage: 'Products will appear here soon.',
                    sectionKey: 'best_sellers',
                  ),

                  // 8. NEW ARRIVALS 2026
                  _buildSectionHeader(
                    context,
                    title: 'New Arrivals 2026',
                    actionLabel: 'Explore',
                    onAction: () => context.go('/products'),
                    isDark: isDark,
                  ),
                  _buildHorizontalProductList(
                    newArrivals,
                    emptyMessage: 'New arrivals will appear here soon.',
                    sectionKey: 'new_arrivals',
                  ),

                  // 9. BULK WHOLESALE DEALS (MOQ >= 10)
                  _buildSectionHeader(
                    context,
                    title: 'Bulk MOQ Deals (Max Discount)',
                    actionLabel: 'See All',
                    onAction: () => context.go('/products'),
                    isDark: isDark,
                  ),
                  _buildHorizontalProductList(
                    wholesaleDeals,
                    emptyMessage: 'No bulk deals available yet.',
                    sectionKey: 'wholesale_deals',
                  ),

                  // 10. RECENTLY VIEWED CAROUSEL
                  _buildSectionHeader(
                    context,
                    title: 'Recently Viewed',
                    actionLabel: '',
                    onAction: null,
                    isDark: isDark,
                  ),
                  _buildHorizontalProductList(
                    allProducts.take(4).toList(),
                    emptyMessage: 'Recently viewed products will appear here.',
                    sectionKey: 'recently_viewed',
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 1. Premium Redesigned Header
  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Container(
        height: 112,
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
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final logoWidth = constraints.maxWidth * 0.60;
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: logoWidth,
                              height: 78,
                              child: Image.asset(
                                'assets/images/RO_LOGO.png',
                                fit: BoxFit.cover,
                                alignment: Alignment.centerLeft,
                                filterQuality: FilterQuality.high,
                                semanticLabel: 'RO Wholesale logo',
                              ),
                            ),
                          );
                        },
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Material(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: () => _openSearchModal(context),
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF1E2D3D)
                    : const Color(0xFFE2E8F0),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded, color: primaryColor),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Search RO systems, membranes, pumps, spares...',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: primaryColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.tune_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 3. Quick Actions Row
  Widget _buildQuickActions(BuildContext context, bool isDark) {
    final actions = [
      {
        'icon': Icons.bolt_rounded,
        'label': 'Bulk Order',
        'color': const Color(0xFF0F62FE),
      },
      {
        'icon': Icons.local_shipping_rounded,
        'label': 'Track Orders',
        'color': const Color(0xFF10B981),
      },
      {
        'icon': Icons.receipt_long_rounded,
        'label': 'GST Invoice',
        'color': const Color(0xFF8B5CF6),
      },
      {
        'icon': Icons.account_balance_wallet_rounded,
        'label': 'Credit Limit',
        'color': const Color(0xFFF59E0B),
      },
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF1E2D3D) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: actions.map((act) {
          final color = act['color'] as Color;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                if (act['label'] == 'Track Orders' ||
                    act['label'] == 'GST Invoice') {
                  context.go('/orders');
                } else if (act['label'] == 'Credit Limit') {
                  context.go('/profile');
                } else {
                  context.go('/products');
                }
              },
              child: Column(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      act['icon'] as IconData,
                      color: color,
                      size: 22,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    act['label'] as String,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white70 : const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // 4. Banner Carousel
  Widget _buildBannerCarousel(BuildContext context, bool isDark) {
    return Column(
      children: [
        SizedBox(
          height: 168,
          child: PageView(
            controller: _bannerPageController,
            onPageChanged: (idx) {
              setState(() {
                _activeBannerIndex = idx;
              });
              _scheduleBannerAdvance();
            },
            children: [
              _buildBannerCard(
                context,
                title: 'B2B WHOLESALE SPECIALS',
                subtitle:
                    'Extra 25% Off on Bulk RO Booster Pumps & 75 GPD Membranes',
                badge: 'GST VERIFIED',
                bgGradient: const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF12377F),
                    Color(0xFF0879D8),
                    Color(0xFF22C3D6),
                  ],
                ),
              ),
              _buildBannerCard(
                context,
                title: '50 LPH COMMERCIAL PLANTS',
                subtitle:
                    'Special Wholesale Price ₹18,900 for Authorized Dealers',
                badge: 'SUPER DEAL',
                bgGradient: const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF0F428F),
                    Color(0xFF087FD0),
                    Color(0xFF27C8D0),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(2, (idx) {
            final isActive = _activeBannerIndex == idx;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: isActive ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFF13B8D5)
                    : (isDark ? Colors.white24 : Colors.black12),
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildBannerCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String badge,
    required LinearGradient bgGradient,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        final imageSize = compact ? 82.0 : 100.0;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            gradient: bgGradient,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0879D8).withValues(alpha: 0.24),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              children: [
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(0.78, -0.2),
                        radius: 1.05,
                        colors: [
                          Color(0x3DFFFFFF),
                          Color(0x1219E5FF),
                          Color(0x000B55B5),
                        ],
                        stops: [0, 0.5, 1],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: -28,
                  top: -52,
                  child: Container(
                    width: 156,
                    height: 156,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                Positioned(
                  right: 92,
                  top: -105,
                  child: Transform.rotate(
                    angle: -0.28,
                    child: Container(
                      width: 34,
                      height: 300,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0),
                            Colors.white.withValues(alpha: 0.075),
                            Colors.white.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 14 : 18,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFD84D),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF06377A)
                                        .withValues(alpha: 0.18),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Text(
                                badge,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: const Color(0xFF123E77),
                                  fontSize: compact ? 8 : 9,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.45,
                                ),
                              ),
                            ),
                            const SizedBox(height: 9),
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: compact ? 14 : 16,
                                height: 1.08,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.25,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: compact ? 10 : 11,
                                height: 1.25,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: compact ? 5 : 10),
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.94, end: 1),
                        duration: const Duration(milliseconds: 650),
                        curve: Curves.easeOutBack,
                        builder: (context, scale, child) =>
                            Transform.scale(scale: scale, child: child),
                        child: AppImage(
                          'assets/images/banner_purifier_transparent.png',
                          width: imageSize,
                          height: imageSize,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.water_drop_rounded,
                            size: imageSize * 0.65,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
          ),
          if (actionLabel != null && actionLabel.isNotEmpty)
            GestureDetector(
              onTap: onAction,
              child: Text(
                '$actionLabel →',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: isDark ? _homeBlueBright : _homeBlue,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCategoriesHorizontalList(
    BuildContext context,
    List<CategoryModel> categories,
    bool isDark,
    Color primaryColor,
  ) {
    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final category = categories[index];
          return SizedBox(
            width: 80,
            child: GestureDetector(
              key: ValueKey('home-category-${category.id}'),
              onTap: () => _pushHomeRoute(
                context,
                ProductListingScreen(
                  initialCategoryId: category.id,
                  initialCategoryName: category.name,
                ),
                useRootNavigator: false,
              ),
              child: Column(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.surfaceDark
                          : const Color(0xFFF1F5F9),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF1E2D3D)
                            : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: ClipOval(
                      child: AppImage(
                        category.imagePath,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) =>
                            Icon(Icons.water_drop_rounded, color: primaryColor),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Text(
                      category.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? Colors.white70
                            : const Color(0xFF0F172A),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Category grid replaces the old single-row icon rail.
  // Horizontal Product Card List Helper
  Widget _buildHorizontalProductList(
    List<ProductModel> products, {
    required String sectionKey,
    required String emptyMessage,
  }) {
    if (products.isEmpty) {
      return Container(
        height: 86,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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

    return SizedBox(
      height: 245,
      child: ListView.builder(
        key: ValueKey('home-products-$sectionKey'),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: products.length,
        itemBuilder: (context, index) {
          final product = products[index];
          final heroTag = 'home_${sectionKey}_${product.id}_0';
          return Container(
            width: 165,
            margin: const EdgeInsets.only(right: 12),
            child: ProductCard(
              product: product,
              isGrid: true,
              heroTag: heroTag,
              showPurchasePrice: false,
              onTap: () => _pushHomeRoute(
                context,
                ProductDetailsScreen(product: product, heroTag: heroTag),
              ),
              onAddToCart: () => addProductToCart(context, ref, product),
            ),
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
    context.push('/cart');
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
                // Back Button
                InkWell(
                  onTap: () => Navigator.pop(context),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.arrow_back_rounded,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Search TextField styled with the Home brand accent.
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _homeBlue, width: 2.2),
                      boxShadow: [
                        BoxShadow(
                          color: _homeBlue.withValues(alpha: 0.16),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      autofocus: true,
                      showCursor: true,
                      cursorColor: _homeBlue,
                      onChanged: (val) => setState(() {}),
                      style: TextStyle(
                        fontSize: 15,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search products...',
                        hintStyle: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF94A3B8),
                          fontWeight: FontWeight.w400,
                        ),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: Color(0xFF94A3B8),
                          size: 22,
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
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Trending Wholesale Searches:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children:
                              [
                                'Filter',
                                'RO Pump',
                                'Membrane',
                                'Pipe',
                                'RO Spares',
                                '50 LPH System',
                              ].map((tag) {
                                return InkWell(
                                  onTap: () {
                                    setState(() {
                                      _searchController.text = tag;
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? const Color(0xFF1E293B)
                                          : const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isDark
                                            ? const Color(0xFF334155)
                                            : const Color(0xFFE2E8F0),
                                      ),
                                    ),
                                    child: Text(
                                      tag,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: isDark
                                            ? Colors.white70
                                            : const Color(0xFF0F172A),
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
