import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../home/presentation/widgets/home_product_card.dart';
import '../providers/wishlist_provider.dart';
import '../widgets/cart_actions.dart';
import 'product_details_screen.dart';

/// Saved products. Same screen on Web and Android.
class WishlistScreen extends ConsumerWidget {
  const WishlistScreen({super.key});

  static const path = '/wishlist';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(wishlistProductsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? null : const Color(0xFFF4F7FB),
      appBar: AppBar(
        title: const Text('My wishlist'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/profile'),
        ),
      ),
      body: products.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFEEF0),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.favorite_outline_rounded,
                        color: Colors.redAccent,
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Your wishlist is empty',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Tap the heart on a product to save it here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => context.go('/products'),
                      child: const Text('Browse catalog'),
                    ),
                  ],
                ),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth.clamp(0.0, 1240.0);
                final columns = width >= 1000 ? 4 : (width >= 640 ? 3 : 2);
                const spacing = 14.0;
                const pad = 16.0;
                final cardWidth =
                    (width - pad * 2 - spacing * (columns - 1)) / columns;
                return Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: width,
                    child: GridView.builder(
                      padding: const EdgeInsets.all(pad),
                      itemCount: products.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: spacing,
                        mainAxisSpacing: spacing,
                        mainAxisExtent: HomeProductCard.extentFor(cardWidth),
                      ),
                      itemBuilder: (context, i) {
                        final product = products[i];
                        final heroTag = 'wishlist_${product.id}';
                        return HomeProductCard(
                          product: product,
                          heroTag: heroTag,
                          onTap: () =>
                              Navigator.of(context, rootNavigator: true).push(
                                MaterialPageRoute(
                                  builder: (_) => ProductDetailsScreen(
                                    product: product,
                                    heroTag: heroTag,
                                  ),
                                ),
                              ),
                          onAddToCart: () =>
                              addProductToCart(context, ref, product),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}
