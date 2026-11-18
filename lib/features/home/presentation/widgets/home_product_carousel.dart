import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import '../../../products/domain/models/product_model.dart';
import 'home_product_card.dart';

/// A horizontal slider of [HomeProductCard]s: [visibleCount] cards fill the
/// width, the rest are reached by swiping, dragging with the mouse, trackpad
/// / shift + wheel, or the arrow buttons. Every product appears once.
class HomeProductCarousel extends StatefulWidget {
  const HomeProductCarousel({
    super.key,
    required this.products,
    required this.visibleCount,
    required this.sectionKey,
    required this.onTap,
    required this.onAddToCart,
    this.spacing = 20,
  });

  final List<ProductModel> products;
  final int visibleCount;
  final String sectionKey;
  final double spacing;
  final void Function(ProductModel product, String heroTag) onTap;
  final void Function(ProductModel product) onAddToCart;

  @override
  State<HomeProductCarousel> createState() => _HomeProductCarouselState();
}

class _HomeProductCarouselState extends State<HomeProductCarousel> {
  final _controller = ScrollController();
  bool _canBack = false;
  bool _canForward = false;
  double _step = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_update);
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  @override
  void didUpdateWidget(covariant HomeProductCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _update() {
    if (!mounted || !_controller.hasClients) return;
    final p = _controller.position;
    final back = p.pixels > 1;
    final forward = p.pixels < p.maxScrollExtent - 1;
    if (back != _canBack || forward != _canForward) {
      setState(() {
        _canBack = back;
        _canForward = forward;
      });
    }
  }

  /// Moves one "page" (the visible cards), snapped to a card edge.
  void _page(int direction) {
    if (!_controller.hasClients || _step <= 0) return;
    final p = _controller.position;
    final current = (p.pixels / _step).round();
    final target = ((current + direction * widget.visibleCount) * _step).clamp(
      0.0,
      p.maxScrollExtent,
    );
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final products = widget.products;
    return LayoutBuilder(
      builder: (context, constraints) {
        final visible = math.max(1, widget.visibleCount);
        final cardWidth =
            (constraints.maxWidth - widget.spacing * (visible - 1)) / visible;
        _step = cardWidth + widget.spacing;
        // Room above and below for the card's hover lift and shadow.
        const lift = 10.0;
        final height = HomeProductCard.extentFor(cardWidth) + lift * 2;
        return SizedBox(
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              ScrollConfiguration(
                // Mouse drag scrolls too (web/desktop), as well as touch.
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.trackpad,
                    PointerDeviceKind.stylus,
                  },
                  scrollbars: false,
                ),
                child: ListView.separated(
                  key: ValueKey('home-carousel-${widget.sectionKey}'),
                  controller: _controller,
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  padding: const EdgeInsets.symmetric(vertical: lift),
                  itemCount: products.length,
                  separatorBuilder: (_, __) => SizedBox(width: widget.spacing),
                  itemBuilder: (context, index) {
                    final product = products[index];
                    final heroTag =
                        'home_${widget.sectionKey}_${product.id}_$index';
                    return SizedBox(
                      width: cardWidth,
                      child: HomeProductCard(
                        key: ValueKey(
                          'home-${widget.sectionKey}-card-${product.id}',
                        ),
                        product: product,
                        heroTag: heroTag,
                        onTap: () => widget.onTap(product, heroTag),
                        onAddToCart: () => widget.onAddToCart(product),
                      ),
                    );
                  },
                ),
              ),
              if (_canBack)
                Positioned(
                  left: -6,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _ArrowButton(
                      key: ValueKey('home-carousel-${widget.sectionKey}-prev'),
                      icon: Icons.chevron_left_rounded,
                      tooltip: 'Previous products',
                      onPressed: () => _page(-1),
                    ),
                  ),
                ),
              if (_canForward)
                Positioned(
                  right: -6,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _ArrowButton(
                      key: ValueKey('home-carousel-${widget.sectionKey}-next'),
                      icon: Icons.chevron_right_rounded,
                      tooltip: 'More products',
                      onPressed: () => _page(1),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: isDark ? const Color(0xFF1E2D3D) : Colors.white,
        shape: const CircleBorder(),
        elevation: 4,
        shadowColor: Colors.black26,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              icon,
              size: 28,
              color: isDark ? Colors.white : const Color(0xFF0B63F6),
            ),
          ),
        ),
      ),
    );
  }
}
