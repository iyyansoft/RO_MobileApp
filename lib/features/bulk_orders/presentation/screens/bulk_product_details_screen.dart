import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/rupee_format.dart';
import '../../../../core/widgets/app_image.dart';
import '../../../products/domain/models/product_model.dart';
import '../../../products/presentation/providers/product_provider.dart';
import '../../domain/bulk_catalog.dart';
import '../bulk_cart_actions.dart';
import '../widgets/bulk_widgets.dart';

/// Bulk Product Details: the same layout as the normal Product Details page
/// (image gallery left, information right on desktop; stacked on phones),
/// with Bulk Orders pricing only: bulk price per piece, minimum pack /
/// order, minimum order value, increment, the pack-step quantity selector,
/// total and Add to Cart (as a bulk line). Never shows the Dealer Price,
/// MRP, unit price or discount.
///
/// Route: /bulk-orders/product/:id?category=<key>, so refresh and direct
/// links keep the bulk context; "Back to Bulk Orders" returns to the same
/// category.
class BulkProductDetailsScreen extends ConsumerWidget {
  const BulkProductDetailsScreen({
    super.key,
    required this.productId,
    this.categoryId,
  });

  static const routePath = 'product/:id';

  final String productId;

  /// The Bulk Orders category it was opened from (e.g. "filters").
  final String? categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProductsProvider);
    final matches = ref
        .watch(allProductsProvider)
        .where((p) => p.id == productId);
    final product = matches.isEmpty ? null : matches.first;
    // Back to the category it came from; for a direct link without one, the
    // product's own Bulk Orders category.
    String? category = categoryId;
    if ((category == null || category.isEmpty) && product != null) {
      for (final c in bulkCategories(ref.watch(categoriesProvider))) {
        if (c.matchesProduct(product)) {
          category = c.id;
          break;
        }
      }
    }
    void back() => context.go(bulkOrdersLocation(category));

    Widget body;
    if (catalog.isLoading && !catalog.hasValue) {
      body = const Center(child: CircularProgressIndicator());
    } else if (product == null || !product.hasBulkOffer) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.inventory_2_outlined,
                size: 44,
                color: kBulkMuted,
              ),
              const SizedBox(height: 12),
              Text(
                product == null
                    ? 'This product is not available.'
                    : '${product.name} is not available in Bulk Orders.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: kBulkMuted),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: back,
                child: const Text('Back to Bulk Orders'),
              ),
            ],
          ),
        ),
      );
    } else {
      body = _BulkDetailsBody(product: product, onBack: back);
    }
    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF0A1118)
          : const Color(0xFFF5F8FC),
      body: SafeArea(bottom: false, child: body),
    );
  }
}

class _BulkDetailsBody extends ConsumerStatefulWidget {
  const _BulkDetailsBody({required this.product, required this.onBack});

  final ProductModel product;
  final VoidCallback onBack;

  @override
  ConsumerState<_BulkDetailsBody> createState() => _BulkDetailsBodyState();
}

class _BulkDetailsBodyState extends ConsumerState<_BulkDetailsBody>
    with BulkQuantityState {
  final _pages = PageController();
  int _image = 0;

  @override
  ProductModel get bulkProduct => widget.product;

  ProductModel get p => widget.product;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  BoxDecoration _card(bool isDark, {double radius = 18}) => BoxDecoration(
    color: isDark ? const Color(0xFF132233) : Colors.white,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: isDark ? const Color(0xFF1E2D3D) : kBulkLine),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFF0F2850).withValues(alpha: isDark ? 0.2 : 0.05),
        blurRadius: 18,
        offset: const Offset(0, 6),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final pad = wide ? 24.0 : 16.0;
        final back = Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('bulk-details-back'),
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text(
              'Back to Bulk Orders',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        );
        final gallery = _gallery(isDark, large: wide);
        final info = _info(isDark, large: wide);
        return SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1300),
              child: Padding(
                padding: EdgeInsets.fromLTRB(pad, 12, pad, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    back,
                    const SizedBox(height: 8),
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 42, child: gallery),
                          const SizedBox(width: 32),
                          Expanded(flex: 58, child: info),
                        ],
                      )
                    else ...[
                      gallery,
                      const SizedBox(height: 16),
                      info,
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _gallery(bool isDark, {required bool large}) {
    final images = p.allImages.isEmpty ? [p.displayImageUrl] : p.allImages;
    final thumb = large ? 68.0 : 52.0;
    return Container(
      key: const ValueKey('bulk-details-gallery'),
      padding: EdgeInsets.all(large ? 16 : 12),
      decoration: _card(isDark, radius: 22),
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                height: large ? 460 : 300,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.03)
                      : const Color(0xFFF7FAFE),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: PageView.builder(
                  controller: _pages,
                  itemCount: images.length,
                  onPageChanged: (i) => setState(() => _image = i),
                  itemBuilder: (context, i) => Padding(
                    padding: EdgeInsets.all(large ? 44 : 20),
                    child: AppImage(
                      images[i],
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(
                          Icons.water_drop_rounded,
                          size: 80,
                          color: kBulkBlue,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const Positioned(
                left: 12,
                top: 12,
                child: BulkPill(
                  text: 'BULK ORDER',
                  color: kBulkBlue,
                  letterSpacing: 0.5,
                  solid: true,
                ),
              ),
            ],
          ),
          if (images.length > 1) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: thumb,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                shrinkWrap: true,
                itemCount: images.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, i) => GestureDetector(
                  onTap: () => _pages.animateToPage(
                    i,
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeInOut,
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: thumb,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: i == _image ? kBulkBlue : kBulkLine,
                        width: i == _image ? 2 : 1,
                      ),
                    ),
                    child: AppImage(images[i], fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _info(bool isDark, {required bool large}) {
    final ink = isDark ? Colors.white : kBulkInk;
    final outOfStock = p.stockStatus == StockStatus.outOfStock;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const BulkPill(text: 'BULK', color: kBulkBlue, letterSpacing: 0.6),
            const SizedBox(width: 8),
            BulkPill.stock(p, key: const ValueKey('bulk-details-stock')),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          p.name,
          key: const ValueKey('bulk-details-name'),
          style: TextStyle(
            fontSize: large ? 28 : 22,
            fontWeight: FontWeight.w900,
            height: 1.2,
            letterSpacing: -0.4,
            color: ink,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'SKU: ${p.sku}  •  Category: ${p.categoryName}',
          style: const TextStyle(
            fontSize: 13,
            color: kBulkMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 18),
        // Bulk price card.
        Container(
          padding: EdgeInsets.all(large ? 20 : 16),
          decoration: _card(isDark),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Bulk Price',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: kBulkMuted,
                ),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: BulkPriceText(
                  key: ValueKey('bulk-price-${p.id}'),
                  product: p,
                  size: large ? 34 : 28,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0F1B2A)
                      : const Color(0xFFF1F6FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: BulkFacts(product: p, fontSize: 13.5),
              ),
              const SizedBox(height: 10),
              Text(
                (p.bulkStep ?? 1) > 1
                    ? 'Sold in packs of ${p.bulkStep}: order ${p.bulkMinQty}, '
                          '${p.bulkMinQty! + p.bulkStep!}, '
                          '${p.bulkMinQty! + 2 * p.bulkStep!} … pieces.'
                    : 'Order at least ${p.bulkMinQty} pieces, then any '
                          'number above.',
                style: const TextStyle(fontSize: 12.5, color: kBulkMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Quantity + total.
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _card(isDark),
          child: Row(
            children: [
              BulkQuantityStepper(
                key: ValueKey('bulk-stepper-${p.id}'),
                productId: p.id,
                quantity: bulkQty,
                canDecrease: canDecrease,
                onDecrease: decrease,
                onIncrease: increase,
                size: 38,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'Total',
                      style: TextStyle(fontSize: 12, color: kBulkMuted),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '₹${formatRupees(p.bulkPrice! * bulkQty)}',
                        key: ValueKey('bulk-total-${p.id}'),
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        BulkAddToCartButton(
          key: ValueKey('bulk-add-${p.id}'),
          adding: bulkAdding,
          enabled: !outOfStock,
          height: 52,
          onPressed: () =>
              addToCart((qty) => addBulkToCart(context, ref, p, qty)),
        ),
        if (p.description.trim().isNotEmpty || p.specifications.isNotEmpty) ...[
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: _card(isDark),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Product details',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: ink,
                  ),
                ),
                if (p.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    p.description.trim(),
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.5,
                      color: kBulkMuted,
                    ),
                  ),
                ],
                for (final e in p.specifications.entries)
                  BulkInfoRow(
                    icon: Icons.label_outline_rounded,
                    label: e.key,
                    value: e.value,
                    fontSize: 13,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
