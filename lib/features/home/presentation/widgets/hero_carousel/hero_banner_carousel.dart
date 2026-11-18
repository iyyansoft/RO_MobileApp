import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../products/domain/models/product_model.dart';
import '../../../../products/presentation/providers/product_provider.dart';
import 'hero_controls.dart';
import 'hero_slide_view.dart';
import 'hero_slides.dart';

export 'hero_slides.dart' show HeroSlide, kHeroSlides;

/// Home banner carousel.
///
/// * Desktop: two slides side by side; tablet and phone: one slide.
/// * Autoplay advances one slide every [autoplayInterval] (5 s). One timer
///   only: it restarts after every slide change (autoplay, arrows, swipe or
///   dots), stops while the pointer is over the carousel and resumes when it
///   leaves.
/// * Loops endlessly in both directions.
/// * Each slide can show live figures for its category from the
///   already-loaded catalogue (no extra API calls).
class HeroBannerCarousel extends ConsumerStatefulWidget {
  const HeroBannerCarousel({
    super.key,
    required this.onNavigate,
    this.slides = kHeroSlides,
    this.autoplayInterval = const Duration(milliseconds: 5000),
  });

  /// Called with the slide's route when its CTA is tapped.
  final ValueChanged<String> onNavigate;
  final List<HeroSlide> slides;
  final Duration autoplayInterval;

  @override
  ConsumerState<HeroBannerCarousel> createState() => _HeroBannerCarouselState();
}

class _HeroBannerCarouselState extends ConsumerState<HeroBannerCarousel>
    with SingleTickerProviderStateMixin {
  // A large virtual page range gives an endless loop in both directions.
  static const _loopBase = 6000;

  /// Space under the cards for their drop shadow.
  static const _shadowRoom = 28.0;

  late int _page = _loopBase - _loopBase % _count;
  PageController? _pageCtrl;
  HeroLayout? _layout;
  Timer? _autoplay;
  bool _hovering = false;

  /// > 0 while an animation started by [_goTo] is running.
  int _programmatic = 0;
  bool _precached = false;

  /// Slow loop shared by every slide's background and product float.
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  );

  int get _count => widget.slides.length;
  int get _slide => _page % _count;

  @override
  void initState() {
    super.initState();
    _scheduleAutoplay();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (heroShouldAnimate(context)) {
      if (!_loop.isAnimating) _loop.repeat();
    } else {
      _loop.stop();
    }
    // Decode every product image up front so slides appear instantly.
    if (!_precached) {
      _precached = true;
      for (final s in widget.slides) {
        precacheImage(AssetImage(s.image), context).ignore();
      }
    }
  }

  @override
  void dispose() {
    _autoplay?.cancel();
    _loop.dispose();
    _pageCtrl?.dispose();
    super.dispose();
  }

  /// One controller per layout (the visible-slide count changes it).
  PageController _controllerFor(HeroLayout layout) {
    if (_pageCtrl == null || _layout != layout) {
      _pageCtrl?.dispose();
      _layout = layout;
      _pageCtrl = PageController(
        initialPage: _page,
        viewportFraction: 1 / layout.visibleSlides,
      );
    }
    return _pageCtrl!;
  }

  /// (Re)starts the single autoplay timer.
  void _scheduleAutoplay() {
    _autoplay?.cancel();
    _autoplay = null;
    if (_hovering) return;
    _autoplay = Timer(widget.autoplayInterval, () => _goTo(_page + 1));
  }

  void _goTo(int page) {
    final ctrl = _pageCtrl;
    if (!mounted || ctrl == null || !ctrl.hasClients) {
      _scheduleAutoplay();
      return;
    }
    // Autoplay, arrows and dots: the 5 s interval restarts now, so slides
    // change exactly every [autoplayInterval].
    _scheduleAutoplay();
    _programmatic++;
    ctrl
        .animateToPage(
          page,
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeInOutCubic,
        )
        .whenComplete(() => _programmatic--);
  }

  /// Jump to slide [index] the short way round.
  void _select(int index) {
    var diff = index - _slide;
    if (diff > _count / 2) diff -= _count;
    if (diff < -_count / 2) diff += _count;
    if (diff != 0) _goTo(_page + diff);
  }

  void _setHovering(bool value) {
    _hovering = value;
    if (value) {
      _autoplay?.cancel();
      _autoplay = null;
    } else {
      _scheduleAutoplay();
    }
  }

  /// Product count and lowest dealer price per slide, from the live catalogue.
  List<HeroSlideStats?> _stats(List<ProductModel> products) => [
    for (final slide in widget.slides)
      () {
        final matches = products.where((p) {
          final category = '${p.categoryId} ${p.categoryName}'.toLowerCase();
          return slide.categoryKeywords.any(category.contains);
        }).toList();
        if (matches.isEmpty) return null;
        final prices = matches.map((p) => p.dealerPrice).where((x) => x > 0);
        return HeroSlideStats(
          count: matches.length,
          fromPrice: prices.isEmpty
              ? 0
              : prices.reduce((a, b) => a < b ? a : b),
        );
      }(),
  ];

  @override
  Widget build(BuildContext context) {
    final stats = _stats(ref.watch(allProductsProvider));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = HeroLayout.forWidth(constraints.maxWidth);
        final ctrl = _controllerFor(layout);
        final compact = layout == HeroLayout.compact;
        final gap = compact ? 8.0 : 12.0; // half the space between cards
        final radius = BorderRadius.circular(compact ? 24 : 28);

        return MouseRegion(
          onEnter: (_) => _setHovering(true),
          onExit: (_) => _setHovering(false),
          child: Column(
            children: [
              SizedBox(
                // Room below the cards for their shadow (the page view clips,
                // so exactly the visible slides are shown).
                height: layout.height + _shadowRoom,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16 - gap),
                      child: Semantics(
                        label:
                            'Featured offers, slide ${_slide + 1} of $_count',
                        child: PageView.builder(
                          controller: ctrl,
                          padEnds: false,
                          onPageChanged: (page) {
                            setState(() => _page = page);
                            // A swipe restarts the interval; our own
                            // animations already did when they started.
                            if (_programmatic == 0) _scheduleAutoplay();
                          },
                          itemBuilder: (context, page) {
                            final index = page % _count;
                            final slide = widget.slides[index];
                            return Padding(
                              padding: EdgeInsets.fromLTRB(
                                gap,
                                0,
                                gap,
                                _shadowRoom,
                              ),
                              child: _Card(
                                radius: radius,
                                child: HeroSlideView(
                                  slide: slide,
                                  layout: layout,
                                  loop: _loop,
                                  stats: stats[index],
                                  onCta: () => widget.onNavigate(slide.route),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    if (!compact) ...[
                      Positioned(
                        left: -6,
                        top: 0,
                        bottom: _shadowRoom,
                        child: Center(
                          child: HeroArrowButton(
                            icon: Icons.chevron_left_rounded,
                            tooltip: 'Previous slide',
                            onTap: () => _goTo(_page - 1),
                          ),
                        ),
                      ),
                      Positioned(
                        right: -6,
                        top: 0,
                        bottom: _shadowRoom,
                        child: Center(
                          child: HeroArrowButton(
                            icon: Icons.chevron_right_rounded,
                            tooltip: 'Next slide',
                            onTap: () => _goTo(_page + 1),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(height: compact ? 0 : 4),
              HeroPagination(
                count: _count,
                index: _slide,
                isDark: isDark,
                onSelect: _select,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Rounded card frame: thin white border and a soft shadow.
class _Card extends StatelessWidget {
  const _Card({required this.radius, required this.child});

  final BorderRadius radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F2850).withValues(alpha: 0.14),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: Colors.white, borderRadius: radius),
        child: ClipRRect(
          borderRadius: radius - const BorderRadius.all(Radius.circular(3)),
          child: child,
        ),
      ),
    );
  }
}
