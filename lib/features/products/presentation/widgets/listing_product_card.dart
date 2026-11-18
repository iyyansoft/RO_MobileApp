import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/widgets/app_image.dart';
import '../../domain/models/product_model.dart';

export '../../../../core/utils/rupee_format.dart';
import '../../../../core/utils/rupee_format.dart';
import 'max_quantity_dialog.dart';
import 'cabinet_price_text.dart';

const _brandBlue = Color(0xFF0B5FC4);
const _buttonBlue = Color(0xFF0B4FB8);
const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _line = Color(0xFFE3EAF3);

/// Card layout used by [ListingProductCard].
enum ListingCardLayout {
  /// Grid cell: image + details on top, quantity and Add to Cart below.
  tile,

  /// Full-width list row: image, details, then quantity and Add to Cart on
  /// the right.
  row,
}

/// Product card for the catalogue listing page.
///
/// Fixed-size image box ([BoxFit.contain], never cropped), consistently
/// aligned brand / name / SKU / MOQ / stock / price / discount, and a
/// quantity selector with an Add to Cart button. Everything comes from the
/// [product] (live API data).
class ListingProductCard extends StatefulWidget {
  const ListingProductCard({
    super.key,
    required this.product,
    required this.onTap,
    required this.onAddToCart,
    this.layout = ListingCardLayout.tile,
    this.isDark = false,
  });

  final ProductModel product;
  final VoidCallback onTap;

  /// Adds [quantity] of the product; resolves to whether it succeeded.
  final Future<bool> Function(int quantity) onAddToCart;
  final ListingCardLayout layout;
  final bool isDark;

  /// Tile height for a given card width (equal for every card in a row).
  static double tileExtent(double width) =>
      40 + math.max(_imageSize(width), 166.0) + 20 + 50;

  static double _imageSize(double width) => (width * 0.34).clamp(104.0, 168.0);

  /// Height of a list row.
  static const rowExtent = 196.0;

  /// Extra height a list row needs for the "Cabinet Price" line; added only
  /// when the page shows a product with one, so other listings are unchanged.
  static const cabinetPriceExtra = 22.0;

  static double rowExtentFor(Iterable<ProductModel> products) =>
      rowExtent +
      (products.any((p) => p.hasCabinetPrice) ? cabinetPriceExtra : 0);

  @override
  State<ListingProductCard> createState() => _ListingProductCardState();
}

class _ListingProductCardState extends State<ListingProductCard> {
  // Orders start at the MOQ (1 when none is set).
  late int _qty = widget.product.minOrderQty;
  bool _adding = false;
  bool _hover = false;

  static const _maxQty = 999;

  Future<void> _add() async {
    if (_adding) return;
    setState(() => _adding = true);
    final ok = await widget.onAddToCart(_qty);
    if (!mounted) return;
    setState(() {
      _adding = false;
      if (ok) _qty = widget.product.minOrderQty;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final surface = isDark ? const Color(0xFF132233) : Colors.white;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        transform: Matrix4.translationValues(0, _hover ? -2 : 0, 0),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: _hover
                ? _brandBlue.withValues(alpha: 0.30)
                : (isDark ? const Color(0xFF1E2D3D) : _line),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F2850)
                  .withValues(alpha: isDark ? 0.3 : (_hover ? 0.10 : 0.05)),
              blurRadius: _hover ? 26 : 18,
              offset: Offset(0, _hover ? 12 : 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(22),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: LayoutBuilder(
                builder: (context, box) =>
                    widget.layout == ListingCardLayout.row
                    ? _row(box.maxWidth)
                    : _tile(box.maxWidth + 40),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tile(double cardWidth) {
    final image = ListingProductCard._imageSize(cardWidth);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ImageBox(product: widget.product, size: image),
              const SizedBox(width: 16),
              Expanded(
                child: _Details(product: widget.product, isDark: widget.isDark),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(height: 50, child: _actions()),
      ],
    );
  }

  Widget _row(double width) {
    final wide = width >= 760;
    return Row(
      children: [
        _ImageBox(product: widget.product, size: 136),
        const SizedBox(width: 20),
        Expanded(
          child: _Details(product: widget.product, isDark: widget.isDark),
        ),
        if (wide) ...[
          const SizedBox(width: 20),
          SizedBox(width: 300, height: 50, child: _actions()),
        ],
      ],
    );
  }

  Widget _actions() {
    // Out of Stock (stock 0) or Below MOQ: nothing can be ordered.
    final outOfStock = !widget.product.canOrder;
    return Row(
      children: [
        _QtySelector(
          value: _qty,
          isDark: widget.isDark,
          onChanged: outOfStock
              ? null
              : (v) {
                  // Above the product maximum: the popup, quantity unchanged.
                  if (widget.product.exceedsMaximum(v)) {
                    showMaxQuantityDialog(
                      context,
                      widget.product.maxOrderQuantity!,
                    );
                    return;
                  }
                  setState(
                    () => _qty = v.clamp(
                      1,
                      widget.product.maxOrderQty ?? _maxQty,
                    ),
                  );
                },
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            key: ValueKey('add-to-cart-${widget.product.id}'),
            onPressed: outOfStock || _adding ? null : _add,
            style: FilledButton.styleFrom(
              backgroundColor: _buttonBlue,
              disabledBackgroundColor: isOutOfStockColor(widget.isDark),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            icon: _adding
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.add_shopping_cart_rounded, size: 20),
            label: Text(
              widget.product.isOutOfStock
                  ? 'Out of Stock'
                  : widget.product.isBelowMoq
                  ? 'Below MOQ'
                  : 'Add to Cart',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }

  static Color isOutOfStockColor(bool isDark) =>
      isDark ? Colors.white12 : const Color(0xFFCBD5E1);
}

class _ImageBox extends StatelessWidget {
  const _ImageBox({required this.product, required this.size});

  final ProductModel product;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F9FD),
        borderRadius: BorderRadius.circular(16),
      ),
      child: AppImage(
        product.displayImageUrl,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.water_drop_rounded, color: _brandBlue, size: 36),
        ),
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.product, required this.isDark});

  final ProductModel product;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? Colors.white : _ink;
    final discount = product.discountPercentage;
    final showMrp = product.mrp > product.dealerPrice;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                product.brand.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _brandBlue,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            const SizedBox(width: 6),
            _StockPill(status: product.stockStatus),
          ],
        ),
        const SizedBox(height: 8),
        // Always two lines tall so prices line up across cards.
        SizedBox(
          height: 44,
          child: Text(
            product.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: ink,
              fontSize: 16.5,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        ),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            [
              if (product.sku.isNotEmpty) 'SKU: ${product.sku}',
              product.moqLabel(),
            ].join('  •  '),
            maxLines: 1,
            style: const TextStyle(
              color: _muted,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 12),
        // One line that scales down on narrow cards, so every card's
        // details block has the same height.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '₹${formatRupees(product.dealerPrice)}',
                style: TextStyle(
                  color: ink,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (showMrp) ...[
                const SizedBox(width: 10),
                Text(
                  '₹${formatRupees(product.mrp)}',
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 13,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ],
              if (discount > 0) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$discount% OFF',
                    style: const TextStyle(
                      color: Color(0xFFDC2626),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        CabinetPriceText(
          product,
          fontSize: 12.5,
          padding: const EdgeInsets.only(top: 4),
        ),
      ],
    );
  }
}

class _StockPill extends StatelessWidget {
  const _StockPill({required this.status});

  final StockStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, fg, bg, icon) = switch (status) {
      StockStatus.inStock => (
        'IN STOCK',
        const Color(0xFF15803D),
        const Color(0xFFDCFCE7),
        Icons.check_rounded,
      ),
      StockStatus.lowStock => (
        'LOW STOCK',
        const Color(0xFFB45309),
        const Color(0xFFFEF3C7),
        Icons.error_outline_rounded,
      ),
      StockStatus.outOfStock => (
        'OUT OF STOCK',
        const Color(0xFFB91C1C),
        const Color(0xFFFEE2E2),
        Icons.block_rounded,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _QtySelector extends StatelessWidget {
  const _QtySelector({
    required this.value,
    required this.onChanged,
    required this.isDark,
  });

  final int value;
  final ValueChanged<int>? onChanged;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    Widget step(IconData icon, int delta, String tip) => IconButton(
      tooltip: tip,
      onPressed: enabled && value + delta >= 1
          ? () => onChanged!(value + delta)
          : null,
      icon: Icon(icon, size: 18),
      color: isDark ? Colors.white : _ink,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 38, height: 48),
      padding: EdgeInsets.zero,
    );
    return Container(
      height: 50,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? const Color(0xFF1E2D3D) : _line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          step(Icons.remove_rounded, -1, 'Decrease quantity'),
          SizedBox(
            width: 34,
            child: Text(
              '$value',
              key: const ValueKey('qty-value'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : _ink,
              ),
            ),
          ),
          step(Icons.add_rounded, 1, 'Increase quantity'),
        ],
      ),
    );
  }
}
