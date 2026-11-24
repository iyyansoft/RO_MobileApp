import 'package:flutter/material.dart';

import '../../../../core/widgets/category_image.dart';

/// Category card for the Home "Categories" row: soft pastel gradient card,
/// large centred product photo on a white tile, compact item-count badge
/// (top-right), and a footer with the category icon, name and an arrow.
/// Lifts gently on hover.
class HomeCategoryCard extends StatefulWidget {
  const HomeCategoryCard({
    super.key,
    required this.name,
    required this.itemCount,
    required this.icon,
    required this.accent,
    required this.gradient,
    required this.onTap,
    this.imageUrl,
    this.assetImage,
    this.placeholderIcon,
    this.compact = false,
  });

  final String name;

  /// Live product count for the category (badge hidden when 0).
  final int itemCount;
  final IconData icon;
  final Color accent;
  final LinearGradient gradient;
  final VoidCallback onTap;

  /// Server image (falls back to the bundled copy, then to [icon]).
  final String? imageUrl;

  /// Bundled image, used when there is no [imageUrl].
  final String? assetImage;

  /// Icon shown in the picture area when there is no picture (defaults to
  /// [icon]); the footer always uses [icon].
  final IconData? placeholderIcon;

  /// Tablet/phone sizing.
  final bool compact;

  /// Card height for the given sizing, so every card in a row matches.
  static double heightFor({required bool compact}) => compact ? 168 : 214;

  @override
  State<HomeCategoryCard> createState() => _HomeCategoryCardState();
}

class _HomeCategoryCardState extends State<HomeCategoryCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final compact = widget.compact;
    final radius = BorderRadius.circular(compact ? 18 : 20);
    final ink = isDark ? Colors.white : const Color(0xFF0F2850);
    final gradient = isDark
        ? LinearGradient(
            begin: widget.gradient.begin,
            end: widget.gradient.end,
            colors: [
              for (final c in widget.gradient.colors)
                Color.alphaBlend(
                  c.withValues(alpha: 0.16),
                  const Color(0xFF142436),
                ),
            ],
          )
        : widget.gradient;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        height: HomeCategoryCard.heightFor(compact: compact),
        transform: Matrix4.translationValues(0, _hover ? -4 : 0, 0),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: radius,
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.10)
                : widget.accent.withValues(alpha: _hover ? 0.32 : 0.16),
          ),
          boxShadow: [
            BoxShadow(
              color: (isDark ? Colors.black : widget.accent).withValues(
                alpha: _hover ? 0.20 : 0.08,
              ),
              blurRadius: _hover ? 22 : 12,
              offset: Offset(0, _hover ? 10 : 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            child: Padding(
              padding: EdgeInsets.all(compact ? 8 : 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Product photo on a white tile, with the count badge.
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(
                              compact ? 12 : 14,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: widget.accent.withValues(alpha: 0.08),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(compact ? 8 : 12),
                            child: AnimatedScale(
                              duration: const Duration(milliseconds: 220),
                              scale: _hover ? 1.05 : 1,
                              child: _image(),
                            ),
                          ),
                        ),
                        if (widget.itemCount > 0)
                          Positioned(
                            top: 6,
                            right: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2.5,
                              ),
                              decoration: BoxDecoration(
                                // Solid so it reads over any photo.
                                color: Colors.white,
                                boxShadow: [
                                  BoxShadow(
                                    color: widget.accent.withValues(
                                      alpha: 0.18,
                                    ),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: widget.accent.withValues(alpha: 0.35),
                                ),
                              ),
                              child: Text(
                                '${widget.itemCount} Items',
                                style: TextStyle(
                                  color: widget.accent,
                                  fontSize: compact ? 9 : 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.1,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(height: compact ? 8 : 10),
                  // Footer: icon, name (up to 2 lines), arrow; fixed height
                  // so every card in the row matches.
                  SizedBox(
                    height: compact ? 30 : 34,
                    child: Row(
                      children: [
                        Container(
                          width: compact ? 24 : 28,
                          height: compact ? 24 : 28,
                          decoration: BoxDecoration(
                            color: isDark
                                ? widget.accent.withValues(alpha: 0.22)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            widget.icon,
                            size: compact ? 14 : 16,
                            color: widget.accent,
                          ),
                        ),
                        SizedBox(width: compact ? 6 : 8),
                        Expanded(
                          child: Text(
                            widget.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: ink,
                              fontSize: compact ? 12 : 12.5,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ),
                        AnimatedSlide(
                          duration: const Duration(milliseconds: 200),
                          offset: Offset(_hover ? 0.2 : 0, 0),
                          child: Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: compact ? 11 : 13,
                            color: widget.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _image() {
    final fallback = Center(
      child: Icon(
        widget.placeholderIcon ?? widget.icon,
        size: 40,
        color: widget.accent,
      ),
    );
    if (widget.imageUrl != null) {
      return CategoryImage(url: widget.imageUrl!, fallback: fallback);
    }
    if (widget.assetImage != null) {
      return Image.asset(
        widget.assetImage!,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => fallback,
      );
    }
    return fallback;
  }
}
