import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../products/domain/models/product_model.dart';
import 'home_product_card.dart';

/// A horizontal slider of [HomeProductCard]s: [visibleCount] cards fill the
/// width.
///
/// * Auto-scroll: when there are more products than fit, the track moves
///   continuously from right to left at [autoScrollSpeed] px/s (very slow,
///   per-frame, no jumps or pauses) and loops forever: after the last
///   product the first follows seamlessly (the same list repeats as you
///   scroll, no data is duplicated). It starts on load/refresh, does not
///   pause on hover, yields while the user drags or an arrow animates, then
///   carries on from there. One ticker, disposed with the widget.
/// * Manual: swipe, mouse drag, trackpad / shift + wheel, or the arrows.
/// * Off in widget tests and when the platform asks to reduce motion, unless
///   [autoScroll] is set explicitly.
class HomeProductCarousel extends StatefulWidget {
  const HomeProductCarousel({
    super.key,
    required this.products,
    required this.visibleCount,
    required this.sectionKey,
    required this.onTap,
    required this.onAddToCart,
    this.spacing = 20,
    this.autoScroll,
    this.autoScrollSpeed = 28,
    this.showCabinetPrice = true,
  });

  /// Passed to every [HomeProductCard] (false: never the Cabinet Price line).
  final bool showCabinetPrice;

  final List<ProductModel> products;
  final int visibleCount;
  final String sectionKey;
  final double spacing;
  final void Function(ProductModel product, String heroTag) onTap;
  final void Function(ProductModel product) onAddToCart;

  /// Force auto-scroll on/off; null = on, except in tests or reduced motion.
  final bool? autoScroll;

  /// Pixels per second.
  final double autoScrollSpeed;

  @override
  State<HomeProductCarousel> createState() => _HomeProductCarouselState();
}

class _HomeProductCarouselState extends State<HomeProductCarousel>
    with SingleTickerProviderStateMixin {
  /// Index of the first product of the "home" copy in the endless list, so
  /// the track can also move backwards (arrows, drag) from the start.
  static const _startCycles = 1000;

  final _controller = ScrollController();
  late final Ticker _ticker = createTicker(_onTick);
  Duration _lastTick = Duration.zero;
  bool _dragging = false;
  bool _animating = false;
  bool _positioned = false;
  double _step = 0;
  bool _canBack = false;
  bool _canForward = false;

  int get _count => widget.products.length;
  bool get _endless => _count > widget.visibleCount;

  bool get _autoScrollEnabled {
    final forced = widget.autoScroll;
    if (forced != null) return forced;
    return !MediaQuery.disableAnimationsOf(context) &&
        WidgetsBinding.instance is WidgetsFlutterBinding;
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateArrows);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant HomeProductCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.products.length != widget.products.length) {
      _positioned = false;
    }
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// One ticker, started/stopped as needed (never duplicated).
  void _syncTicker() {
    final run = _endless && _autoScrollEnabled;
    if (run && !_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (_dragging || _animating || !_controller.hasClients) return;
    // Clamp long gaps (tab in the background) so it never jumps.
    final delta = widget.autoScrollSpeed * dt.clamp(0.0, 0.05);
    _controller.jumpTo(_controller.position.pixels + delta);
  }

  /// Place the track at the first product of the home copy.
  void _positionStart() {
    if (_positioned || !_endless || _step <= 0) return;
    _positioned = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      _controller.jumpTo(_startCycles * _count * _step);
      _updateArrows();
    });
  }

  void _updateArrows() {
    if (!mounted || !_controller.hasClients) return;
    final p = _controller.position;
    final back = _endless || p.pixels > 1;
    final forward = _endless || p.pixels < p.maxScrollExtent - 1;
    if (back != _canBack || forward != _canForward) {
      setState(() {
        _canBack = back;
        _canForward = forward;
      });
    }
  }

  /// Moves one "page" (the visible cards), snapped to a card edge.
  Future<void> _page(int direction) async {
    if (!_controller.hasClients || _step <= 0) return;
    final p = _controller.position;
    final current = (p.pixels / _step).round();
    var target = (current + direction * widget.visibleCount) * _step;
    if (!_endless) target = target.clamp(0.0, p.maxScrollExtent);
    _animating = true;
    try {
      await _controller.animateTo(
        target,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    } finally {
      _animating = false;
    }
  }

  bool _onScrollNotification(ScrollNotification n) {
    if (n is ScrollStartNotification && n.dragDetails != null) {
      _dragging = true;
    } else if (n is ScrollEndNotification) {
      _dragging = false;
    }
    return false;
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
        _positionStart();
        // Room above and below for the card's hover lift and shadow.
        const lift = 10.0;
        final height = HomeProductCard.extentFor(cardWidth) + lift * 2;

        Widget card(int index) {
          final product = products[index % products.length];
          final cycle =
              index ~/ products.length - (_endless ? _startCycles : 0);
          final heroTag = 'home_${widget.sectionKey}_${product.id}_$index';
          return Padding(
            padding: EdgeInsets.only(right: widget.spacing),
            child: SizedBox(
              width: cardWidth,
              child: HomeProductCard(
                // Unique per copy; the home copy keeps the plain key.
                key: ValueKey(
                  'home-${widget.sectionKey}-card-${product.id}'
                  '${cycle == 0 ? '' : '-$cycle'}',
                ),
                product: product,
                heroTag: heroTag,
                showCabinetPrice: widget.showCabinetPrice,
                onTap: () => widget.onTap(product, heroTag),
                onAddToCart: () => widget.onAddToCart(product),
              ),
            ),
          );
        }

        return SizedBox(
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              NotificationListener<ScrollNotification>(
                onNotification: _onScrollNotification,
                child: ScrollConfiguration(
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
                  child: ListView.builder(
                    key: ValueKey('home-carousel-${widget.sectionKey}'),
                    controller: _controller,
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    padding: const EdgeInsets.symmetric(vertical: lift),
                    // Endless: the same products repeat in both directions.
                    itemCount: _endless ? null : products.length,
                    itemExtent: _step,
                    itemBuilder: (context, index) => card(index),
                  ),
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
