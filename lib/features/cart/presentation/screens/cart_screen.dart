import '../../../../core/widgets/app_image.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/loading_skeleton.dart';
import '../../../../core/widgets/responsive_layout.dart';
import '../../../products/domain/models/product_model.dart';
import '../../../products/presentation/widgets/max_quantity_dialog.dart';
import '../../domain/order_pricing.dart';
import '../providers/cart_provider.dart';
import '../../domain/models/cart_item_model.dart';
import '../../../products/presentation/widgets/cabinet_price_text.dart';
import '../../../../core/widgets/app_toast.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? AppColors.accentDark : AppColors.primaryLight;
    final cartState = ref.watch(cartProvider);
    // Live totals with the server's pricing rules (no GST in the cart).
    final totals = ref.watch(cartTotalsProvider(false));
    ref.listen<CartState>(cartProvider, (previous, next) {
      if (next.errorMessage != null &&
          next.errorMessage != previous?.errorMessage) {
        AppToast.error(context, next.errorMessage!);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'B2B Wholesale Cart (${cartState.items.length})',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 17,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        elevation: 0,
        backgroundColor: isDark
            ? AppColors.backgroundDark
            : AppColors.backgroundLight,
        actions: [
          if (cartState.items.isNotEmpty)
            TextButton.icon(
              onPressed: () {
                _showClearCartDialog(context, ref);
              },
              icon: const Icon(
                Icons.delete_sweep_rounded,
                size: 18,
                color: Colors.redAccent,
              ),
              label: const Text(
                'Clear',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: cartState.isLoading
            ? _buildSkeletonLoading()
            : cartState.items.isEmpty
            ? _buildEmptyCart(context, isDark, primaryColor)
            : ResponsiveContentWrapper(
                maxWidth: 1000,
                child: Column(
                  children: [
                    // Cart Items & Summary Scrollable View
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // GST Tax Benefit Alert Card
                            _buildGstAlertBanner(isDark, primaryColor),
                            const SizedBox(height: 16),

                            // Items List
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: cartState.items.length,
                              itemBuilder: (context, index) {
                                final item = cartState.items[index];
                                return _buildCartItemCard(
                                  context,
                                  ref,
                                  item,
                                  isDark,
                                  primaryColor,
                                );
                              },
                            ),
                            const SizedBox(height: 16),

                            // Cart Summary Breakdown Card
                            _buildCartSummaryCard(
                              context,
                              totals,
                              isDark,
                              primaryColor,
                              hasBulk: ref
                                  .watch(cartProvider)
                                  .items
                                  .any((i) => i.isBulk),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Sticky Bottom Checkout Action Section
                    _buildStickyBottomCheckout(
                      context,
                      cartState,
                      isDark,
                      primaryColor,
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildGstAlertBanner(bool isDark, Color primaryColor) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF10B981).withValues(alpha: 0.3),
        ),
      ),
      child: const Row(
        children: [
          Icon(Icons.verified_rounded, color: Color(0xFF10B981), size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'GST Input Tax Credit Invoice will be issued for this order.',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF10B981),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartItemCard(
    BuildContext context,
    WidgetRef ref,
    dynamic item,
    bool isDark,
    Color primaryColor,
  ) {
    final product = item.product as ProductModel;
    final quantity = item.quantity as int;
    final itemTotal = item.totalPrice as double;
    // Bulk lines: bulk price per piece, minimum + whole steps (never mixed
    // with the Dealer Price).
    final line = item as CartItemModel;
    final bulk = line.isBulk;
    final step = bulk ? (product.bulkStep ?? 1) : 1;
    final atBulkMin = bulk && quantity <= (product.bulkMinQty ?? quantity);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF1E2D3D) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image Container
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 80,
              height: 80,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : const Color(0xFFF8FAFC),
              padding: const EdgeInsets.all(6),
              child: AppImage(
                product.displayImageUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) =>
                    Icon(Icons.water_drop_rounded, color: primaryColor),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Details & Controls
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      product.brand.toUpperCase(),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: primaryColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        size: 18,
                        color: Colors.grey,
                      ),
                      onPressed: () {
                        ref.read(cartProvider.notifier).removeItem(product.id);
                        AppToast.success(
                          context,
                          'Removed ${product.name} from cart.',
                        );
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                if (bulk)
                  Container(
                    key: ValueKey('cart-bulk-badge-${product.id}'),
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B5FC4).withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'BULK ORDER',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0B5FC4),
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  bulk
                      ? 'SKU: ${product.sku} • Bulk ${formatInr(line.unitPrice)} / piece'
                      : 'SKU: ${product.sku} • ${formatInr(product.dealerPrice)} / Unit',
                  key: ValueKey('cart-unit-price-${product.id}'),
                  style: const TextStyle(fontSize: 10.5, color: Colors.grey),
                ),
                if (bulk)
                  Text(
                    'Minimum ${product.bulkMinQty} • '
                    '${step > 1 ? 'packs of $step' : 'then +1'} '
                    '(${product.bulkPackLabel})',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: Color(0xFF0B5FC4),
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else
                  CabinetPriceText(
                    product,
                    fontSize: 10.5,
                    padding: const EdgeInsets.only(top: 2),
                  ),
                const SizedBox(height: 8),

                // Quantity Row & Total Price
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Quantity Controller
                    Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.04)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDark ? Colors.white10 : Colors.black12,
                        ),
                      ),
                      child: Row(
                        children: [
                          GestureDetector(
                            key: ValueKey('cart-minus-${product.id}'),
                            // Bulk: disabled at the minimum (use the bin to
                            // remove the line).
                            onTap: atBulkMin
                                ? null
                                : () {
                                    ref
                                        .read(cartProvider.notifier)
                                        .updateQuantity(
                                          product.id,
                                          quantity - step,
                                        );
                                  },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              child: Icon(
                                Icons.remove_rounded,
                                size: 16,
                                color: atBulkMin ? Colors.grey.shade400 : null,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              '$quantity',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF0F172A),
                              ),
                            ),
                          ),
                          GestureDetector(
                            key: ValueKey('cart-plus-${product.id}'),
                            onTap: () {
                              if (bulk) {
                                ref
                                    .read(cartProvider.notifier)
                                    .updateQuantity(
                                      product.id,
                                      quantity + step,
                                    );
                                return;
                              }
                              // Product maximum (PDF quantity): the popup.
                              if (product.exceedsMaximum(quantity + 1)) {
                                showMaxQuantityDialog(
                                  context,
                                  product.maxOrderQuantity!,
                                );
                                return;
                              }
                              ref
                                  .read(cartProvider.notifier)
                                  .updateQuantity(product.id, quantity + 1);
                            },
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              child: Icon(Icons.add_rounded, size: 16),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 8),
                    // Total Item Price (shrinks on narrow phones).
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          formatInr(itemTotal),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF0F172A),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartSummaryCard(
    BuildContext context,
    OrderTotals totals,
    bool isDark,
    Color primaryColor, {
    bool hasBulk = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF1E2D3D) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Order Cost Summary',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 14),
          _buildSummaryRow(
            'Subtotal (${totals.itemCount} Pcs)',
            formatInr(totals.subtotal),
            isDark,
          ),
          const SizedBox(height: 8),
          _buildSummaryRow(
            discountLabel(totals.rules, hasBulk: hasBulk),
            '- ${formatInr(totals.discount)}',
            isDark,
            isDiscount: true,
          ),
          const SizedBox(height: 8),
          _buildSummaryRow('GST', 'Added at checkout', isDark),
          const SizedBox(height: 8),
          _buildSummaryRow(
            'Delivery / Freight',
            totals.freeDelivery ? 'FREE' : formatInr(totals.deliveryFee),
            isDark,
            isHighlight: totals.freeDelivery,
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Grand Total',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(width: 10),
              // Large totals shrink to fit narrow phones.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    formatInr(totals.grandTotal),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: primaryColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: isDark ? 0.12 : 0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 15, color: primaryColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No GST added in cart. Choose With GST or Without GST at checkout.',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white70 : const Color(0xFF334155),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(
    String label,
    String value,
    bool isDark, {
    bool isDiscount = false,
    bool isHighlight = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Long labels wrap instead of pushing the amount off screen.
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          value,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: isDiscount
                ? const Color(0xFF10B981)
                : (isHighlight
                      ? AppColors.primaryLight
                      : (isDark ? Colors.white : const Color(0xFF0F172A))),
          ),
        ),
      ],
    );
  }

  Widget _buildStickyBottomCheckout(
    BuildContext context,
    dynamic cartState,
    bool isDark,
    Color primaryColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF1E2D3D) : const Color(0xFFE2E8F0),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 48,
              child: OutlinedButton(
                onPressed: () {
                  context.go('/products');
                },
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Continue Shopping',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () {
                  // Every line must be orderable: MOQ <= quantity <= stock
                  // (checkout refuses it otherwise).
                  final problems = <String>[];
                  for (final item in cartState.items as List) {
                    final product = item.product as ProductModel;
                    final quantity = item.quantity as int;
                    // Bulk lines follow the bulk rule (minimum + steps,
                    // stock); the normal maximum does not apply to them.
                    if ((item as CartItemModel).isBulk) {
                      final problem = product.bulkQuantityProblem(quantity);
                      if (problem != null) problems.add(problem);
                      continue;
                    }
                    // Above the product maximum: the same popup.
                    if (product.exceedsMaximum(quantity)) {
                      showMaxQuantityDialog(context, product.maxOrderQuantity!);
                      return;
                    }
                    final problem = product.quantityProblem(quantity);
                    if (problem != null) problems.add(problem);
                  }
                  if (problems.isNotEmpty) {
                    AppToast.error(
                      context,
                      '${problems.join(' ')} Update or remove ${problems.length == 1 ? 'it' : 'them'} to check out.',
                    );
                    return;
                  }
                  context.push('/checkout');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                label: const Text(
                  'Checkout',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCart(
    BuildContext context,
    bool isDark,
    Color primaryColor,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primaryColor.withValues(alpha: 0.12),
              ),
              child: Icon(
                Icons.remove_shopping_cart_rounded,
                size: 52,
                color: primaryColor,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Your B2B Wholesale Cart is Empty',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Explore our catalog of RO membranes, pumps, filters & spares to start bulk ordering.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                context.go('/products');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.storefront_rounded),
              label: const Text(
                'Browse Categories',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonLoading() {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          LoadingSkeleton.rectangular(
            width: double.infinity,
            height: 100,
            borderRadius: 16,
          ),
          SizedBox(height: 12),
          LoadingSkeleton.rectangular(
            width: double.infinity,
            height: 100,
            borderRadius: 16,
          ),
          SizedBox(height: 12),
          LoadingSkeleton.rectangular(
            width: double.infinity,
            height: 180,
            borderRadius: 16,
          ),
        ],
      ),
    );
  }

  void _showClearCartDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Clear Cart?'),
          content: const Text(
            'Are you sure you want to remove all items from your wholesale cart?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                ref.read(cartProvider.notifier).clearCart();
                Navigator.pop(context);
              },
              child: const Text(
                'Clear All',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        );
      },
    );
  }
}
