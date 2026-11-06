import 'package:flutter/material.dart';

import '../../../../core/widgets/app_image.dart';
import '../../../products/domain/models/product_model.dart';

/// Product card for the Home page grids (Best Sellers etc.).
///
/// Compact, content-sized layout: tinted image stage with discount + stock
/// badges, brand/SKU line, name, MOQ chip, and a price block with the saving
/// and an Add button. Lifts, tints its border and zooms the image on hover.
class HomeProductCard extends StatefulWidget {
  const HomeProductCard({
    super.key,
    required this.product,
    required this.onTap,
    required this.onAddToCart,
    this.heroTag,
  });

  final ProductModel product;
  final VoidCallback onTap;
  final VoidCallback onAddToCart;
  final String? heroTag;

  /// Height the grid should give each card (content-sized, no empty gap).
  static double extentFor(double cardWidth) =>
      (cardWidth * 0.88 + 168).clamp(300.0, 540.0);

  @override
  State<HomeProductCard> createState() => _HomeProductCardState();
}

class _HomeProductCardState extends State<HomeProductCard> {
  bool _hovered = false;

  static const _accent = Color(0xFF0B63F6);

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final saving = (p.mrp - p.dealerPrice).clamp(0, double.infinity);

    final surface = isDark ? const Color(0xFF132233) : Colors.white;
    final border = _hovered
        ? _accent.withValues(alpha: 0.35)
        : (isDark ? const Color(0xFF1E2D3D) : const Color(0xFFE8EEF5));
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final muted = isDark ? Colors.white54 : const Color(0xFF94A3B8);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _hovered ? -4 : 0, 0),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: border),
          boxShadow: [
            BoxShadow(
              color: (_hovered ? _accent : const Color(0xFF0F2850)).withValues(
                alpha: isDark ? 0.25 : (_hovered ? 0.14 : 0.05),
              ),
              blurRadius: _hovered ? 26 : 12,
              offset: Offset(0, _hovered ? 12 : 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 210;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Image stage ─────────────────────────────────
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: isDark
                                ? null
                                : const RadialGradient(
                                    center: Alignment(0, -0.1),
                                    radius: 0.9,
                                    colors: [
                                      Color(0xFFFFFFFF),
                                      Color(0xFFEFF5FC),
                                    ],
                                  ),
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.04)
                                : null,
                          ),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    6,
                                    compact ? 26 : 22,
                                    6,
                                    compact ? 24 : 6,
                                  ),
                                  child: AnimatedScale(
                                    scale: _hovered ? 1.05 : 1.0,
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeOutCubic,
                                    child: Hero(
                                      tag:
                                          widget.heroTag ??
                                          'product_img_${p.id}_0',
                                      child: AppImage(
                                        p.displayImageUrl,
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) => Icon(
                                          Icons.water_drop_outlined,
                                          size: 48,
                                          color: _accent.withValues(alpha: 0.4),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (p.discountPercentage > 0)
                                Positioned(
                                  top: 8,
                                  left: 8,
                                  child: _DiscountBadge(p.discountPercentage),
                                ),
                              // Narrow cards: stock pill moves to the bottom
                              // so it never collides with the discount badge.
                              Positioned(
                                top: compact ? null : 8,
                                bottom: compact ? 8 : null,
                                right: compact ? null : 8,
                                left: compact ? 8 : null,
                                child: _StockPill(p.stockStatus),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // ── Details ─────────────────────────────────────
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        compact ? 10 : 14,
                        10,
                        compact ? 10 : 14,
                        compact ? 10 : 14,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  p.brand.toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _accent,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                              if (p.sku.isNotEmpty && !compact) ...[
                                Text(
                                  '  •  ',
                                  style: TextStyle(color: muted, fontSize: 9),
                                ),
                                Flexible(
                                  child: Text(
                                    p.sku,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: muted,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          SizedBox(
                            // Reserve two lines so prices line up across cards.
                            height: compact ? 32 : 38,
                            child: Text(
                              p.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: titleColor,
                                fontSize: compact ? 13 : 15,
                                fontWeight: FontWeight.w700,
                                height: 1.22,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          _MoqChip(moq: p.moq, isDark: isDark),
                          SizedBox(height: compact ? 10 : 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (saving > 0)
                                      Text(
                                        'Save ₹${saving.toStringAsFixed(0)}',
                                        style: const TextStyle(
                                          color: Color(0xFF059669),
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    Wrap(
                                      crossAxisAlignment:
                                          WrapCrossAlignment.end,
                                      spacing: 6,
                                      children: [
                                        Text(
                                          '₹${p.dealerPrice.toStringAsFixed(0)}',
                                          style: TextStyle(
                                            color: titleColor,
                                            fontSize: compact ? 17 : 20,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -0.4,
                                          ),
                                        ),
                                        if (p.mrp > p.dealerPrice)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 3,
                                            ),
                                            child: Text(
                                              '₹${p.mrp.toStringAsFixed(0)}',
                                              style: TextStyle(
                                                color: muted,
                                                fontSize: 11,
                                                decoration:
                                                    TextDecoration.lineThrough,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              _AddButton(
                                compact: compact,
                                highlighted: _hovered,
                                onPressed: widget.onAddToCart,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _DiscountBadge extends StatelessWidget {
  const _DiscountBadge(this.percent);
  final int percent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF43F5E), Color(0xFFF97316)],
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF43F5E).withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        '$percent% OFF',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _StockPill extends StatelessWidget {
  const _StockPill(this.status);
  final StockStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      StockStatus.inStock => const Color(0xFF059669),
      StockStatus.lowStock => const Color(0xFFD97706),
      StockStatus.outOfStock => const Color(0xFF64748B),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            status.label,
            style: TextStyle(
              color: color,
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _MoqChip extends StatelessWidget {
  const _MoqChip({required this.moq, required this.isDark});
  final int moq;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final fg = isDark ? Colors.white70 : const Color(0xFF475569);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, size: 11, color: fg),
          const SizedBox(width: 4),
          Text(
            'MOQ $moq ${moq == 1 ? 'pc' : 'pcs'}',
            style: TextStyle(
              color: fg,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({
    required this.compact,
    required this.highlighted,
    required this.onPressed,
  });

  final bool compact;
  final bool highlighted;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF0B63F6);
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF3B82F6), blue],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: blue.withValues(alpha: highlighted ? 0.4 : 0.25),
              blurRadius: highlighted ? 14 : 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 9 : 14,
              vertical: compact ? 9 : 10,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.add_shopping_cart_rounded,
                  color: Colors.white,
                  size: compact ? 16 : 17,
                ),
                if (!compact) ...[
                  const SizedBox(width: 6),
                  const Text(
                    'Add',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
