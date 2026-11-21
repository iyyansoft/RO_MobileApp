import 'package:flutter/material.dart';

import '../../../../core/utils/rupee_format.dart';
import '../../../products/domain/models/product_model.dart';
import '../../domain/bulk_catalog.dart';

/// Shared Bulk Orders building blocks (product card and Bulk Product
/// Details): price facts, the pack-step quantity selector and Add to Cart.
/// They only ever show bulk pricing (never Dealer Price, MRP or discount).
const kBulkBlue = Color(0xFF0B5FC4);
const kBulkDeepBlue = Color(0xFF0B4FB8);
const kBulkInk = Color(0xFF0F172A);
const kBulkMuted = Color(0xFF64748B);
const kBulkLine = Color(0xFFE3EAF3);
const _green = Color(0xFF059669);
const _red = Color(0xFFDC2626);

/// Small rounded label, e.g. "BULK" or "In stock".
class BulkPill extends StatelessWidget {
  const BulkPill({
    super.key,
    required this.text,
    required this.color,
    this.icon,
    this.letterSpacing = 0,
    this.solid = false,
  });

  final String text;
  final Color color;
  final IconData? icon;
  final double letterSpacing;

  /// White-backed (over images) instead of a tint.
  final bool solid;

  /// In stock / Out of stock for [product].
  factory BulkPill.stock(ProductModel product, {Key? key}) {
    final out = product.stockStatus == StockStatus.outOfStock;
    return BulkPill(
      key: key,
      text: out ? 'Out of stock' : 'In stock',
      color: out ? _red : _green,
      icon: out ? Icons.block_rounded : Icons.check_rounded,
      solid: true,
    );
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: solid ? Colors.white : color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(999),
      border: solid ? Border.all(color: color.withValues(alpha: 0.25)) : null,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
        ],
        Text(
          text,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: letterSpacing,
            color: color,
          ),
        ),
      ],
    ),
  );
}

/// "₹170 / piece" in blue.
class BulkPriceText extends StatelessWidget {
  const BulkPriceText({super.key, required this.product, this.size = 22});

  final ProductModel product;
  final double size;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '₹${formatRupees(product.bulkPrice!)}',
            style: TextStyle(
              fontSize: size,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
              color: isDark ? Colors.white : kBulkDeepBlue,
            ),
          ),
          TextSpan(
            text: ' / piece',
            style: TextStyle(
              fontSize: size * 0.6,
              fontWeight: FontWeight.w600,
              color: kBulkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Minimum pack / order, minimum order value and increment rows.
class BulkFacts extends StatelessWidget {
  const BulkFacts({super.key, required this.product, this.fontSize = 12.5});

  final ProductModel product;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final p = product;
    return Column(
      children: [
        BulkInfoRow(
          key: ValueKey('bulk-min-${p.id}'),
          icon: Icons.inventory_2_outlined,
          label: bulkMinimumLabel(p),
          value: p.bulkPackLabel!,
          fontSize: fontSize,
        ),
        BulkInfoRow(
          key: ValueKey('bulk-min-value-${p.id}'),
          icon: Icons.payments_outlined,
          label: 'Minimum Order Value',
          value: '₹${formatRupees(p.bulkMinimumOrderValue!)}',
          fontSize: fontSize,
        ),
        BulkInfoRow(
          key: ValueKey('bulk-step-${p.id}'),
          icon: Icons.add_circle_outline_rounded,
          label: 'Increment',
          value: bulkIncrementLabel(p),
          fontSize: fontSize,
        ),
      ],
    );
  }
}

class BulkInfoRow extends StatelessWidget {
  const BulkInfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.fontSize = 12.5,
  });

  final IconData icon;
  final String label;
  final String value;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        children: [
          Icon(
            icon,
            size: fontSize + 2,
            color: kBulkBlue.withValues(alpha: 0.8),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: fontSize - 0.5, color: kBulkMuted),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : kBulkInk,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pack-step quantity selector (state lives in the parent, which also
/// applies the rule; minus is disabled at the minimum).
class BulkQuantityStepper extends StatelessWidget {
  const BulkQuantityStepper({
    super.key,
    required this.productId,
    required this.quantity,
    required this.canDecrease,
    required this.onDecrease,
    required this.onIncrease,
    this.size = 32,
  });

  final String productId;
  final int quantity;
  final bool canDecrease;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final double size;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Widget button(IconData icon, VoidCallback? onTap, String key, String tip) {
      final enabled = onTap != null;
      return Tooltip(
        message: tip,
        child: Material(
          color: enabled
              ? (isDark ? const Color(0xFF1E2D3D) : Colors.white)
              : Colors.transparent,
          shape: CircleBorder(
            side: BorderSide(color: enabled ? kBulkLine : Colors.transparent),
          ),
          child: InkWell(
            key: ValueKey(key),
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(
                icon,
                size: size * 0.56,
                color: enabled
                    ? (isDark ? Colors.white : kBulkDeepBlue)
                    : const Color(0xFFCBD5E1),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(
            Icons.remove_rounded,
            canDecrease ? onDecrease : null,
            'bulk-minus-$productId',
            'Decrease',
          ),
          ConstrainedBox(
            constraints: BoxConstraints(minWidth: size * 1.45),
            child: Text(
              '$quantity',
              key: ValueKey('bulk-qty-$productId'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: size * 0.47,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white : kBulkInk,
              ),
            ),
          ),
          button(
            Icons.add_rounded,
            onIncrease,
            'bulk-plus-$productId',
            'Increase',
          ),
        ],
      ),
    );
  }
}

/// Full-width Add to Cart with a press animation and a loading state.
class BulkAddToCartButton extends StatefulWidget {
  const BulkAddToCartButton({
    super.key,
    required this.adding,
    required this.enabled,
    required this.onPressed,
    this.height = 44,
  });

  final bool adding;
  final bool enabled;
  final VoidCallback onPressed;
  final double height;

  @override
  State<BulkAddToCartButton> createState() => _BulkAddToCartButtonState();
}

class _BulkAddToCartButtonState extends State<BulkAddToCartButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && !widget.adding;
    return Listener(
      onPointerDown: (_) => setState(() => _down = true),
      onPointerUp: (_) => setState(() => _down = false),
      onPointerCancel: (_) => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down && active ? 0.97 : 1,
        duration: const Duration(milliseconds: 110),
        child: SizedBox(
          height: widget.height,
          child: ElevatedButton(
            onPressed: active ? widget.onPressed : null,
            style:
                ElevatedButton.styleFrom(
                  backgroundColor: kBulkDeepBlue,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: widget.adding
                      ? kBulkDeepBlue.withValues(alpha: 0.75)
                      : const Color(0xFFCBD5E1),
                  disabledForegroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ).copyWith(
                  overlayColor: WidgetStatePropertyAll(
                    Colors.white.withValues(alpha: 0.10),
                  ),
                ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.adding)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                else
                  const Icon(Icons.add_shopping_cart_rounded, size: 18),
                const SizedBox(width: 8),
                Text(
                  !widget.enabled
                      ? 'Out of Stock'
                      : (widget.adding ? 'Adding…' : 'Add to Cart'),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: widget.height >= 50 ? 16 : 14.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Quantity state shared by the card and the details page: starts at the
/// minimum; steps by the product's step; never below the minimum.
mixin BulkQuantityState<T extends StatefulWidget> on State<T> {
  ProductModel get bulkProduct;
  late int bulkQty = bulkProduct.bulkMinQty ?? 1;
  bool bulkAdding = false;

  int get bulkMin => bulkProduct.bulkMinQty ?? 1;
  int get bulkStep => bulkProduct.bulkStep ?? 1;
  bool get canDecrease => bulkQty - bulkStep >= bulkMin;

  // Re-checked here so quick repeated taps never go below the minimum.
  void decrease() {
    if (canDecrease) setState(() => bulkQty -= bulkStep);
  }

  void increase() => setState(() => bulkQty += bulkStep);

  Future<void> addToCart(Future<bool> Function(int quantity) add) async {
    if (bulkAdding) return;
    setState(() => bulkAdding = true);
    try {
      final ok = await add(bulkQty);
      if (ok && mounted) setState(() => bulkQty = bulkMin);
    } finally {
      if (mounted) setState(() => bulkAdding = false);
    }
  }
}
