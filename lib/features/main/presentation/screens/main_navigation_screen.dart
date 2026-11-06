import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/brand_logo.dart';
import '../../../../core/widgets/responsive_layout.dart';
import '../../../cart/presentation/providers/cart_provider.dart';

class MainNavigationScreen extends ConsumerWidget {
  final Widget child;

  const MainNavigationScreen({super.key, required this.child});

  int _calculateSelectedIndex(BuildContext context) {
    try {
      final String location = GoRouterState.of(context).uri.path;
      if (location.startsWith('/products') ||
          location.startsWith('/categories')) {
        return 1;
      }
      if (location.startsWith('/orders')) return 2;
      if (location.startsWith('/profile')) return 3;
      if (location.startsWith('/cart')) return 4;
    } catch (_) {}
    return 0; // default is /home
  }

  void _onItemTapped(int index, BuildContext context) {
    try {
      switch (index) {
        case 0:
          context.go('/home');
          break;
        case 1:
          context.go('/products');
          break;
        case 2:
          context.go('/orders');
          break;
        case 3:
          context.go('/profile');
          break;
        case 4:
          context.go('/cart');
          break;
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedIndex = _calculateSelectedIndex(context);
    final cartState = ref.watch(cartProvider);
    final cartCount = cartState.totalItemCount;

    final Color activeColor = isDark
        ? AppColors.accentDark
        : const Color(0xFF1976D2);
    final Color inactiveColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);
    final Color barBackground = isDark ? AppColors.surfaceDark : Colors.white;
    final Color borderColor = isDark
        ? const Color(0xFF1E2D3D)
        : const Color(0xFFE2E8F0);

    final isDesktop = context.isDesktop;

    if (isDesktop) {
      return Scaffold(
        backgroundColor: isDark
            ? AppColors.backgroundDark
            : AppColors.backgroundLight,
        body: Column(
          children: [
            // Responsive Desktop/Web Header Navigation Bar
            Container(
              height: 68,
              decoration: BoxDecoration(
                color: barBackground,
                border: Border(
                  bottom: BorderSide(color: borderColor, width: 1.0),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
                    offset: const Offset(0, 2),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: ResponsiveContentWrapper(
                maxWidth: 1360,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    // Brand Logo (Prominent, uncropped)
                    InkWell(
                      onTap: () => _onItemTapped(0, context),
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: BrandLogo(
                          width: 190,
                          height: 52,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const Spacer(),
                    // Desktop Navigation Items (Scrollable if tightly sized)
                    Flexible(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildWebNavItem(
                              context,
                              index: 0,
                              icon: Icons.home_outlined,
                              activeIcon: Icons.home_rounded,
                              label: 'Home',
                              isSelected: selectedIndex == 0,
                              activeColor: activeColor,
                              inactiveColor: inactiveColor,
                            ),
                            const SizedBox(width: 4),
                            _buildWebNavItem(
                              context,
                              index: 1,
                              icon: Icons.grid_view_outlined,
                              activeIcon: Icons.grid_view_rounded,
                              label: 'Categories',
                              isSelected: selectedIndex == 1,
                              activeColor: activeColor,
                              inactiveColor: inactiveColor,
                            ),
                            const SizedBox(width: 4),
                            _buildWebNavItem(
                              context,
                              index: 2,
                              icon: Icons.receipt_long_outlined,
                              activeIcon: Icons.receipt_long_rounded,
                              label: 'Orders',
                              isSelected: selectedIndex == 2,
                              activeColor: activeColor,
                              inactiveColor: inactiveColor,
                            ),
                            const SizedBox(width: 4),
                            _buildWebNavItem(
                              context,
                              index: 3,
                              icon: Icons.person_outline_rounded,
                              activeIcon: Icons.person_rounded,
                              label: 'Profile',
                              isSelected: selectedIndex == 3,
                              activeColor: activeColor,
                              inactiveColor: inactiveColor,
                            ),
                            const SizedBox(width: 10),
                            // Desktop Cart Button with Badge
                            _buildWebCartButton(
                              context,
                              isSelected: selectedIndex == 4,
                              cartCount: cartCount,
                              activeColor: activeColor,
                              inactiveColor: inactiveColor,
                              isDark: isDark,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Centered responsive page body
            Expanded(
              child: ResponsiveContentWrapper(
                maxWidth: 1360,
                child: child,
              ),
            ),
          ],
        ),
      );
    }

    // Mobile & Tablet Navigation: Exact 5-tab Bottom Navigation Bar
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    const barHeight = 60.0;

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      body: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(
              bottom: barHeight + bottomPadding,
            ),
            child: child,
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: barHeight + bottomPadding,
              padding: EdgeInsets.only(bottom: bottomPadding),
              decoration: BoxDecoration(
                color: barBackground,
                border: Border(
                  top: BorderSide(color: borderColor, width: 0.8),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                    offset: const Offset(0, -2),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildNavItem(
                      context,
                      index: 0,
                      icon: Icons.home_outlined,
                      activeIcon: Icons.home_rounded,
                      label: 'Home',
                      isSelected: selectedIndex == 0,
                      activeColor: activeColor,
                      inactiveColor: inactiveColor,
                    ),
                  ),
                  Expanded(
                    child: _buildNavItem(
                      context,
                      index: 1,
                      icon: Icons.grid_view_outlined,
                      activeIcon: Icons.grid_view_rounded,
                      label: 'Categories',
                      isSelected: selectedIndex == 1,
                      activeColor: activeColor,
                      inactiveColor: inactiveColor,
                    ),
                  ),
                  Expanded(
                    child: _buildNavItem(
                      context,
                      index: 2,
                      icon: Icons.receipt_long_outlined,
                      activeIcon: Icons.receipt_long_rounded,
                      label: 'Orders',
                      isSelected: selectedIndex == 2,
                      activeColor: activeColor,
                      inactiveColor: inactiveColor,
                    ),
                  ),
                  Expanded(
                    child: _buildNavItem(
                      context,
                      index: 3,
                      icon: Icons.person_outline_rounded,
                      activeIcon: Icons.person_rounded,
                      label: 'Profile',
                      isSelected: selectedIndex == 3,
                      activeColor: activeColor,
                      inactiveColor: inactiveColor,
                    ),
                  ),
                  Expanded(
                    child: _buildNavItem(
                      context,
                      index: 4,
                      icon: Icons.shopping_cart_outlined,
                      activeIcon: Icons.shopping_cart_rounded,
                      label: 'Cart',
                      isSelected: selectedIndex == 4,
                      activeColor: activeColor,
                      inactiveColor: inactiveColor,
                      badgeCount: cartCount,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebNavItem(
    BuildContext context, {
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required bool isSelected,
    required Color activeColor,
    required Color inactiveColor,
  }) {
    const effectiveActiveColor = Color(0xFF0284C7);
    const effectiveInactiveColor = Color(0xFF334155);

    return InkWell(
      onTap: () => _onItemTapped(index, context),
      borderRadius: BorderRadius.circular(20),
      hoverColor: effectiveActiveColor.withValues(alpha: 0.06),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFDCEEFE)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? activeIcon : icon,
              color: isSelected ? effectiveActiveColor : effectiveInactiveColor,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? effectiveActiveColor : effectiveInactiveColor,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebCartButton(
    BuildContext context, {
    required bool isSelected,
    required int cartCount,
    required Color activeColor,
    required Color inactiveColor,
    required bool isDark,
  }) {
    const effectiveActiveColor = Color(0xFF0284C7);
    const effectiveInactiveColor = Color(0xFF334155);

    return InkWell(
      onTap: () => _onItemTapped(4, context),
      borderRadius: BorderRadius.circular(20),
      hoverColor: effectiveActiveColor.withValues(alpha: 0.06),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFDCEEFE)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  isSelected
                      ? Icons.shopping_cart_rounded
                      : Icons.shopping_cart_outlined,
                  color: isSelected ? effectiveActiveColor : effectiveInactiveColor,
                  size: 20,
                ),
                if (cartCount > 0)
                  Positioned(
                    top: -6,
                    right: -10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4.5,
                        vertical: 1.5,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 17,
                        minHeight: 17,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark ? AppColors.surfaceDark : Colors.white,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        cartCount > 99 ? '99+' : '$cartCount',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 8),
            Text(
              'Cart',
              style: TextStyle(
                color: isSelected ? effectiveActiveColor : effectiveInactiveColor,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context, {
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required bool isSelected,
    required Color activeColor,
    required Color inactiveColor,
    int badgeCount = 0,
  }) {
    return InkWell(
      onTap: () => _onItemTapped(index, context),
      splashColor: activeColor.withValues(alpha: 0.08),
      highlightColor: Colors.transparent,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  isSelected ? activeIcon : icon,
                  color: isSelected ? activeColor : inactiveColor,
                  size: 24,
                ),
                if (badgeCount > 0)
                  Positioned(
                    top: -4,
                    right: -10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4.5,
                        vertical: 1.5,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? AppColors.surfaceDark
                              : Colors.white,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        badgeCount > 99 ? '99+' : '$badgeCount',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isSelected ? activeColor : inactiveColor,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 11,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
