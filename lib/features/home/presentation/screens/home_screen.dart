import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/loading_skeleton.dart';
import '../../../products/domain/models/category_model.dart';
import '../../../products/domain/models/product_model.dart';
import '../../../products/presentation/providers/product_provider.dart';
import '../../../products/presentation/screens/product_details_screen.dart';
import '../../../products/presentation/screens/product_listing_screen.dart';
import '../../../products/presentation/widgets/product_card.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _isLoading = true;
  int _activeBannerIndex = 0;
  final PageController _bannerPageController = PageController();

  @override
  void initState() {
    super.initState();
    // Fast 500ms initial load simulation for instant dashboard response
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _bannerPageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? AppColors.accentDark : AppColors.primaryLight;
    final categories = ref.watch(categoriesProvider);
    final allProducts = ref.watch(allProductsProvider);

    final featuredProducts = allProducts.where((p) => p.isFeatured).toList();
    final bestSellers = allProducts.where((p) => p.discountPercentage >= 30).toList();
    final newArrivals = allProducts.reversed.take(4).toList();
    final wholesaleDeals = allProducts.where((p) => p.moq >= 10).toList();

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            setState(() => _isLoading = true);
            await Future.delayed(const Duration(milliseconds: 600));
            if (mounted) setState(() => _isLoading = false);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. PREMIUM APP HEADER (Dealer Greeting, Profile, Notifications & Cart)
                _buildHeader(context, isDark, primaryColor),

                if (_isLoading)
                  _buildSkeletonDashboard()
                else ...[
                  // 2. SEARCH BAR & QUICK FILTER
                  _buildSearchBar(context, isDark, primaryColor),

                  // 3. QUICK ACTIONS GRID (Bulk Order, Track, GST Invoice, Credit)
                  _buildQuickActions(context, isDark, primaryColor),

                  // 4. B2B PROMOTIONAL BANNER CAROUSEL
                  _buildBannerCarousel(context, isDark, primaryColor),

                  // 5. CATEGORIES SECTION (Horizontal Scroll)
                  _buildSectionHeader(
                    context,
                    title: 'Categories',
                    actionLabel: 'View All (14)',
                    onAction: () => context.go('/products'),
                    isDark: isDark,
                  ),
                  _buildCategoriesHorizontalList(context, categories, isDark, primaryColor),

                  // 6. FEATURED WHOLESALE DEALS (Horizontal Scroll Product Cards)
                  _buildSectionHeader(
                    context,
                    title: 'Featured Wholesale Deals',
                    actionLabel: 'View All',
                    onAction: () => context.go('/products'),
                    isDark: isDark,
                  ),
                  _buildHorizontalProductList(featuredProducts),

                  // 7. BEST SELLERS SECTION
                  _buildSectionHeader(
                    context,
                    title: 'Best Sellers',
                    actionLabel: 'Explore',
                    onAction: () => context.go('/products'),
                    isDark: isDark,
                  ),
                  _buildHorizontalProductList(bestSellers),

                  // 8. NEW ARRIVALS 2026
                  _buildSectionHeader(
                    context,
                    title: 'New Arrivals 2026',
                    actionLabel: 'Explore',
                    onAction: () => context.go('/products'),
                    isDark: isDark,
                  ),
                  _buildHorizontalProductList(newArrivals),

                  // 9. BULK WHOLESALE DEALS (MOQ >= 10)
                  _buildSectionHeader(
                    context,
                    title: 'Bulk MOQ Deals (Max Discount)',
                    actionLabel: 'See All',
                    onAction: () => context.go('/products'),
                    isDark: isDark,
                  ),
                  _buildHorizontalProductList(wholesaleDeals),

                  // 10. RECENTLY VIEWED CAROUSEL
                  _buildSectionHeader(
                    context,
                    title: 'Recently Viewed',
                    actionLabel: '',
                    onAction: null,
                    isDark: isDark,
                  ),
                  _buildHorizontalProductList(allProducts.take(4).toList()),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 1. Premium Header
  Widget _buildHeader(BuildContext context, bool isDark, Color primaryColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Dealer Info & Greeting
          Row(
            children: [
              GestureDetector(
                onTap: () => context.go('/profile'),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0F62FE), Color(0xFF00C6FF)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0F62FE).withOpacity(0.3),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      'RK',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Welcome, Rajesh Kumar!',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.verified_rounded, size: 14, color: Color(0xFF10B981)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Aqua Tech Solutions • Gold Dealer',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Action Buttons (Notification & Cart)
          Row(
            children: [
              // Notification Bell
              _buildHeaderIconButton(
                icon: Icons.notifications_outlined,
                badgeCount: 3,
                isDark: isDark,
                onTap: () => _showNotificationModal(context),
              ),
              const SizedBox(width: 8),
              // Cart Shortcut
              _buildHeaderIconButton(
                icon: Icons.shopping_cart_outlined,
                badgeCount: 2,
                isDark: isDark,
                onTap: () => _showCartDrawerModal(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderIconButton({
    required IconData icon,
    required int badgeCount,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? const Color(0xFF1E2D3D) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, size: 20, color: isDark ? Colors.white : const Color(0xFF0F172A)),
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
                  constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
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
    );
  }

  // 2. Search Bar
  Widget _buildSearchBar(BuildContext context, bool isDark, Color primaryColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark ? const Color(0xFF1E2D3D) : const Color(0xFFE2E8F0),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: TextField(
          readOnly: true,
          onTap: () => context.go('/products'),
          decoration: InputDecoration(
            hintText: 'Search RO systems, membranes, pumps, spares...',
            hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
            prefixIcon: Icon(Icons.search_rounded, color: primaryColor),
            suffixIcon: Container(
              margin: const EdgeInsets.all(6),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.tune_rounded, color: Colors.white, size: 18),
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }

  // 3. Quick Actions Row
  Widget _buildQuickActions(BuildContext context, bool isDark, Color primaryColor) {
    final actions = [
      {'icon': Icons.bolt_rounded, 'label': 'Bulk Order', 'color': const Color(0xFF0F62FE)},
      {'icon': Icons.local_shipping_rounded, 'label': 'Track Orders', 'color': const Color(0xFF10B981)},
      {'icon': Icons.receipt_long_rounded, 'label': 'GST Invoice', 'color': const Color(0xFF8B5CF6)},
      {'icon': Icons.account_balance_wallet_rounded, 'label': 'Credit Limit', 'color': const Color(0xFFF59E0B)},
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? const Color(0xFF1E2D3D) : const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: actions.map((act) {
          final color = act['color'] as Color;
          return GestureDetector(
            onTap: () {
              if (act['label'] == 'Track Orders') {
                context.go('/orders');
              } else if (act['label'] == 'Credit Limit') {
                context.go('/profile');
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Opening ${act['label']} Portal...'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              }
            },
            child: Column(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(act['icon'] as IconData, color: color, size: 22),
                ),
                const SizedBox(height: 6),
                Text(
                  act['label'] as String,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white70 : const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // 4. Banner Carousel
  Widget _buildBannerCarousel(BuildContext context, bool isDark, Color primaryColor) {
    return Column(
      children: [
        SizedBox(
          height: 160,
          child: PageView(
            controller: _bannerPageController,
            onPageChanged: (idx) {
              setState(() {
                _activeBannerIndex = idx;
              });
            },
            children: [
              _buildBannerCard(
                context,
                title: 'B2B WHOLESALE SPECIALS',
                subtitle: 'Extra 25% Off on Bulk RO Booster Pumps & 75 GPD Membranes',
                badge: 'GST VERIFIED',
                bgGradient: const LinearGradient(colors: [Color(0xFF051838), Color(0xFF0F62FE)]),
              ),
              _buildBannerCard(
                context,
                title: '50 LPH COMMERCIAL PLANTS',
                subtitle: 'Special Wholesale Price ₹18,900 for Authorized Dealers',
                badge: 'SUPER DEAL',
                bgGradient: const LinearGradient(colors: [Color(0xFF0D3E9D), Color(0xFF00C6FF)]),
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
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: isActive ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: isActive ? primaryColor : (isDark ? Colors.white24 : Colors.black12),
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
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: bgGradient,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F62FE).withOpacity(0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00F5D4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(
                      color: Color(0xFF051838),
                      fontSize: 8.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Image.asset(
            'assets/images/purifier.jpg',
            width: 90,
            height: 90,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(Icons.water_drop_rounded, size: 60, color: Colors.white),
          ),
        ],
      ),
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
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
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
                  color: isDark ? AppColors.accentDark : AppColors.primaryLight,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // 5. Horizontal Categories List
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
          final cat = categories[index];
          return Container(
            width: 80,
            margin: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () {
                ref.read(productFilterProvider.notifier).selectCategory(cat.id);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ProductListingScreen(initialCategoryName: cat.name),
                  ),
                );
              },
              child: Column(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.surfaceDark : const Color(0xFFF1F5F9),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark ? const Color(0xFF1E2D3D) : const Color(0xFFE2E8F0),
                      ),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: ClipOval(
                      child: Image.asset(
                        cat.imagePath,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Icon(Icons.water_drop_rounded, color: primaryColor),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    cat.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white70 : const Color(0xFF0F172A),
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

  // Horizontal Product Card List Helper
  Widget _buildHorizontalProductList(List<ProductModel> products) {
    return SizedBox(
      height: 245,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: products.length,
        itemBuilder: (context, index) {
          final product = products[index];
          return Container(
            width: 165,
            margin: const EdgeInsets.only(right: 12),
            child: ProductCard(
              product: product,
              isGrid: true,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ProductDetailsScreen(product: product),
                  ),
                );
              },
              onAddToCart: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Added ${product.name} to Cart!'),
                    backgroundColor: const Color(0xFF10B981),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  // Skeleton Loader for Dashboard
  Widget _buildSkeletonDashboard() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: const [
          LoadingSkeleton.rectangular(height: 48, borderRadius: 16),
          SizedBox(height: 16),
          LoadingSkeleton.rectangular(height: 70, borderRadius: 16),
          SizedBox(height: 16),
          LoadingSkeleton.rectangular(height: 150, borderRadius: 20),
          SizedBox(height: 16),
          LoadingSkeleton.rectangular(height: 180, borderRadius: 16),
        ],
      ),
    );
  }

  void _showNotificationModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Dealer Notifications (3)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Divider(),
              const ListTile(
                leading: Icon(Icons.local_shipping_rounded, color: Colors.blue),
                title: Text('Order #ORD-2026-982 Dispatched'),
                subtitle: Text('Tracking ID: TRK984210'),
              ),
              const ListTile(
                leading: Icon(Icons.verified_rounded, color: Colors.green),
                title: Text('GST Tax Credit Invoiced'),
                subtitle: Text('Claim ₹4,250 input tax credit'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showCartDrawerModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('B2B Wholesale Cart (2 Items)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Divider(),
              const ListTile(
                title: Text('Vontron 75 GPD RO Membrane'),
                subtitle: Text('MOQ: 10 Pcs • ₹820 / Unit'),
                trailing: Text('₹8,200', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  context.go('/orders');
                },
                child: const Text('Proceed to B2B Checkout'),
              ),
            ],
          ),
        );
      },
    );
  }
}
