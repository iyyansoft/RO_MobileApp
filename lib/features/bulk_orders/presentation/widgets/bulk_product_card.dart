import 'package:flutter/material.dart';

import '../../../../core/utils/rupee_format.dart';
import '../../../../core/widgets/app_image.dart';
import '../../../products/domain/models/product_model.dart';
import 'bulk_widgets.dart';

/// Bulk Orders product card, styled like the normal catalogue cards: a large
/// product image (the visual focus) with the BULK badge and stock status,
/// then name, SKU, bulk price per piece and the bulk facts, and finally the
/// pack-step quantity selector, total and Add to Cart.
///
/// Tapping the image / information area opens the Bulk Product Details page
/// ([onOpen]); the quantity buttons and Add to Cart are separate controls
/// and never navigate. Never shows the Dealer Price, MRP or discount.
class BulkProductCard extends StatefulWidget {
  const BulkProductCard({
    super.key,
    required this.product,
    required this.onAddToCart,
    required this.onOpen,
    this.isDark = false,
  });

  /// Card height used by the Bulk Orders grid (all cards align).
  static const extent = 508.0;

  final ProductModel product;

  /// Adds the quantity in bulk; resolves to whether it succeeded.
  final Future<bool> Function(int quantity) onAddToCart;

  /// Opens the Bulk Product Details page.
  final VoidCallback onOpen;
  final bool isDark;

  @override
  State<BulkProductCard> createState() => _BulkProductCardState();
}

class _BulkProductCardState extends State<BulkProductCard>
    with BulkQuantityState {
  bool _hover = false;

  ProductModel get p => widget.product;

  @override
  ProductModel get bulkProduct => widget.product;

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final ink = isDark ? Colors.white : kBulkInk;
    final outOfStock = p.stockStatus == StockStatus.outOfStock;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        key: ValueKey('bulk-card-${p.id}'),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hover ? -4 : 0, 0),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF132233) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _hover
                ? kBulkBlue.withValues(alpha: 0.30)
                : (isDark ? const Color(0xFF1E2D3D) : kBulkLine),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F2850)
                  .withValues(alpha: isDark ? 0.3 : (_hover ? 0.12 : 0.05)),
              blurRadius: _hover ? 26 : 16,
              offset: Offset(0, _hover ? 12 : 5),
            ),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image + information: opens the details page.
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                key: ValueKey('bulk-open-${p.id}'),
                behavior: HitTestBehavior.opaque,
                onTap: widget.onOpen,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      height: 176,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.04)
                            : const Color(0xFFF7FAFE),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                18,
                                26,
                                18,
                                12,
                              ),
                              child: AnimatedScale(
                                scale: _hover ? 1.04 : 1,
                                duration: const Duration(milliseconds: 220),
                                child: AppImage(
                                  p.displayImageUrl,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => const Center(
                                    child: Icon(
                                      Icons.water_drop_rounded,
                                      size: 44,
                                      color: kBulkBlue,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const Positioned(
                            left: 10,
                            top: 10,
                            child: BulkPill(
                              text: 'BULK',
                              color: kBulkBlue,
                              letterSpacing: 0.6,
                              solid: true,
                            ),
                          ),
                          Positioned(
                            right: 10,
                            top: 10,
                            child: BulkPill.stock(
                              p,
                              key: ValueKey('bulk-stock-${p.id}'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 40,
                      child: Text(
                        p.name,
                        key: ValueKey('bulk-name-${p.id}'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                          color: _hover && !isDark ? kBulkDeepBlue : ink,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'SKU: ${p.sku}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: kBulkMuted),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF0F1B2A)
                            : const Color(0xFFF1F6FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: BulkPriceText(
                              key: ValueKey('bulk-price-${p.id}'),
                              product: p,
                            ),
                          ),
                          BulkFacts(product: p, fontSize: 12),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            // Actions (never navigate).
            Row(
              children: [
                BulkQuantityStepper(
                  key: ValueKey('bulk-stepper-${p.id}'),
                  productId: p.id,
                  quantity: bulkQty,
                  canDecrease: canDecrease,
                  onDecrease: decrease,
                  onIncrease: increase,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'Total',
                        style: TextStyle(fontSize: 11, color: kBulkMuted),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '₹${formatRupees(p.bulkPrice! * bulkQty)}',
                          key: ValueKey('bulk-total-${p.id}'),
                          style: TextStyle(
                            fontSize: 18,
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
            const SizedBox(height: 12),
            BulkAddToCartButton(
              key: ValueKey('bulk-add-${p.id}'),
              adding: bulkAdding,
              enabled: !outOfStock,
              onPressed: () => addToCart(widget.onAddToCart),
            ),
          ],
        ),
      ),
    );
  }
}
