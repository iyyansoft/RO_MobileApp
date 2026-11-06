import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/widgets/brand_logo.dart';
import '../../../products/domain/models/category_model.dart';

/// Site footer for the Home page: brand, quick links, categories, account
/// links, service highlights and a copyright bar.
///
/// Deep blue gradient with cyan accents, an animated wave along the top edge,
/// slowly drifting glow orbs and a large, subtle NeeroPlus logo watermark.
/// Motion pauses for reduced-motion users and in widget tests.
class HomeFooter extends StatefulWidget {
  const HomeFooter({
    super.key,
    required this.categories,
    required this.onNavigate,
    required this.onCategoryTap,
    this.bottomInset = 0,
  });

  final List<CategoryModel> categories;

  /// Called with an app route such as '/orders'.
  final ValueChanged<String> onNavigate;
  final ValueChanged<CategoryModel> onCategoryTap;

  /// Extra space at the bottom (e.g. for a mobile bottom navigation bar),
  /// painted with the footer colour so no gap shows.
  final double bottomInset;

  static const _text = Color(0xFFD3E2F2);
  static const _muted = Color(0xFF8FA8C6);
  static const _cyan = Color(0xFF22D3EE);

  @override
  State<HomeFooter> createState() => _HomeFooterState();
}

class _HomeFooterState extends State<HomeFooter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animate =
        !MediaQuery.disableAnimationsOf(context) &&
        WidgetsBinding.instance is WidgetsFlutterBinding;
    if (!animate) {
      _loop.stop();
    } else if (!_loop.isAnimating) {
      _loop.repeat();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;
    return ClipRect(
      child: Stack(
        children: [
          // ── Animated backdrop: gradient, glows, watermark, top wave ──
          Positioned.fill(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _loop,
                builder: (context, _) => _Backdrop(t: _loop.value),
              ),
            ),
          ),

          // ── Content ──
          Padding(
            padding: EdgeInsets.only(bottom: widget.bottomInset),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1240),
                child: LayoutBuilder(
                  builder: (context, c) => _content(context, c.maxWidth, year),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, double width, int year) {
    final wide = width >= 900;
    final medium = width >= 600;
    final pad = wide ? 32.0 : 22.0;

    final brand = _BrandBlock(wide: wide);
    final quick = _LinkColumn(
      title: 'Quick links',
      links: [
        ('Home', () => widget.onNavigate('/home')),
        ('Categories', () => widget.onNavigate('/categories')),
        ('All products', () => widget.onNavigate('/products')),
        ('Cart', () => widget.onNavigate('/cart')),
      ],
    );
    final shop = _LinkColumn(
      title: 'Shop by category',
      links: [
        for (final cat in widget.categories.take(6))
          (cat.name, () => widget.onCategoryTap(cat)),
        if (widget.categories.isEmpty)
          ('Browse catalog', () => widget.onNavigate('/products')),
      ],
    );
    final account = _LinkColumn(
      title: 'Your account',
      links: [
        ('My orders', () => widget.onNavigate('/orders')),
        ('Track orders', () => widget.onNavigate('/orders')),
        ('GST invoices', () => widget.onNavigate('/orders')),
        ('Profile', () => widget.onNavigate('/profile')),
      ],
    );

    Widget columns;
    if (wide) {
      columns = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 14, child: brand),
          const SizedBox(width: 40),
          Expanded(flex: 7, child: quick),
          Expanded(flex: 8, child: shop),
          Expanded(flex: 7, child: account),
        ],
      );
    } else {
      final links = medium
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: quick),
                Expanded(child: shop),
                Expanded(child: account),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: quick),
                    const SizedBox(width: 12),
                    Expanded(child: account),
                  ],
                ),
                const SizedBox(height: 26),
                // Categories as a two-column list on phones: tidier and
                // shorter than one long column.
                _LinkColumn(
                  title: 'Shop by category',
                  columns: 2,
                  links: [
                    for (final cat in widget.categories.take(6))
                      (cat.name, () => widget.onCategoryTap(cat)),
                    if (widget.categories.isEmpty)
                      ('Browse catalog', () => widget.onNavigate('/products')),
                  ],
                ),
              ],
            );
      columns = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [brand, const SizedBox(height: 30), links],
      );
    }

    return Padding(
      // Extra top space leaves room for the animated wave edge.
      padding: EdgeInsets.fromLTRB(pad, wide ? 72 : 58, pad, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          columns,
          SizedBox(height: wide ? 40 : 30),
          // Glowing gradient divider.
          Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  HomeFooter._cyan.withValues(alpha: 0),
                  HomeFooter._cyan.withValues(alpha: 0.55),
                  HomeFooter._cyan.withValues(alpha: 0),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Wrap(
              alignment: wide
                  ? WrapAlignment.spaceBetween
                  : WrapAlignment.center,
              runAlignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 6,
              children: [
                Text(
                  '© $year Neero+. All rights reserved.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: HomeFooter._muted,
                    fontSize: 12,
                  ),
                ),
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.water_drop_rounded,
                      size: 12,
                      color: HomeFooter._cyan,
                    ),
                    SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        'Wholesale prices for registered dealers',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: HomeFooter._muted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Closing wordmark: the full NeeroPlus logo, centred and upright
          // in its own space (never cut off or behind text), with a slow
          // light shimmer sweeping across it.
          Padding(
            padding: EdgeInsets.only(bottom: wide ? 28 : 20),
            child: Center(
              child: _ShimmerWordmark(
                loop: _loop,
                width: math.min(width * 0.82, wide ? 640.0 : 420.0),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Large faint white silhouette of the logo with an animated light sweep.
class _ShimmerWordmark extends StatelessWidget {
  const _ShimmerWordmark({required this.loop, required this.width});

  final Animation<double> loop;
  final double width;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: loop,
        builder: (context, child) {
          // Sweep runs across during the first ~40% of each loop, then rests.
          final p = (loop.value / 0.4).clamp(0.0, 1.0);
          final x = -1.6 + 3.2 * Curves.easeInOut.transform(p);
          return ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment(x - 0.6, -0.4),
              end: Alignment(x + 0.6, 0.4),
              colors: [
                Colors.white.withValues(alpha: 0.09),
                const Color(0xFF7DE3F4).withValues(alpha: 0.30),
                Colors.white.withValues(alpha: 0.09),
              ],
              stops: const [0.3, 0.5, 0.7],
            ).createShader(bounds),
            child: child,
          );
        },
        child: Image.asset(
          'assets/images/RO_LOGO.png',
          width: width,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}

/// Gradient, drifting glows and the animated top wave.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.t});

  /// Animation phase, 0..1 (loops seamlessly).
  final double t;

  @override
  Widget build(BuildContext context) {
    const tau = math.pi * 2;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = c.maxHeight;

        Widget glow(double size, Color color, double alpha) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: alpha),
                color.withValues(alpha: 0),
              ],
            ),
          ),
        );

        return Stack(
          children: [
            // Base gradient: deep navy → ocean blue.
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF071A33),
                      Color(0xFF0A2A52),
                      Color(0xFF06345E),
                      Color(0xFF041327),
                    ],
                    stops: [0, 0.4, 0.7, 1],
                  ),
                ),
              ),
            ),
            // Drifting cyan / blue glows.
            Positioned(
              left: w * (0.62 + 0.08 * math.sin(t * tau)) - 220,
              top: h * (0.18 + 0.05 * math.cos(t * tau)) - 220,
              child: glow(440, const Color(0xFF22D3EE), 0.22),
            ),
            Positioned(
              left: w * (0.12 + 0.06 * math.cos(t * tau)) - 200,
              top: h * (0.78 + 0.05 * math.sin(t * tau)) - 200,
              child: glow(400, const Color(0xFF3B82F6), 0.20),
            ),
            // Animated wave edge along the top (page colour → footer).
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 46,
              child: CustomPaint(
                painter: _TopWavePainter(
                  t,
                  // Matches the bottom of the Home page background.
                  pageColor: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF0F1A24)
                      : Colors.white,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Two flowing waves that blend the page background into the footer, with a
/// thin cyan crest line.
class _TopWavePainter extends CustomPainter {
  _TopWavePainter(this.t, {required this.pageColor});
  final double t;
  final Color pageColor;

  @override
  void paint(Canvas canvas, Size size) {
    const tau = math.pi * 2;
    final w = size.width;
    final h = size.height;

    Path wave(double base, double amp, double cycles, double phase) {
      final path = Path()..moveTo(0, 0);
      for (var i = 0; i <= 60; i++) {
        final x = w * i / 60;
        final y = base + math.sin(i / 60 * tau * cycles + phase) * amp;
        path.lineTo(x, y);
      }
      return path
        ..lineTo(w, 0)
        ..close();
    }

    // Page-coloured cut-out so the footer starts with a soft wave.
    final page = Paint()..color = pageColor;
    canvas.drawPath(wave(h * 0.45, h * 0.18, 1.3, t * tau), page);
    canvas.drawPath(
      wave(h * 0.6, h * 0.14, 2.1, -t * tau * 2),
      Paint()..color = pageColor.withValues(alpha: 0.35),
    );

    // Cyan crest following the front wave.
    final crest = Path();
    for (var i = 0; i <= 60; i++) {
      final x = w * i / 60;
      final y = h * 0.45 + math.sin(i / 60 * tau * 1.3 + t * tau) * h * 0.18;
      i == 0 ? crest.moveTo(x, y) : crest.lineTo(x, y);
    }
    canvas.drawPath(
      crest,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2)
        ..color = HomeFooter._cyan.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(covariant _TopWavePainter old) =>
      old.t != t || old.pageColor != pageColor;
}

class _BrandBlock extends StatelessWidget {
  const _BrandBlock({required this.wide});
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Logo on a white chip with a soft cyan glow.
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: HomeFooter._cyan.withValues(alpha: 0.35),
                blurRadius: 24,
                spreadRadius: -2,
              ),
            ],
          ),
          child: const BrandLogo(
            width: 156,
            height: 52,
            onDark: true,
            alignment: Alignment.centerLeft,
          ),
        ),
        const SizedBox(height: 18),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: const Text(
            'Wholesale RO water purifiers, membranes, filters, pumps and '
            'spare parts for authorised dealers.',
            style: TextStyle(
              color: HomeFooter._text,
              fontSize: 14,
              height: 1.55,
            ),
          ),
        ),
        const SizedBox(height: 18),
        const Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Highlight(Icons.verified_rounded, 'Genuine spares'),
            _Highlight(Icons.receipt_long_rounded, 'GST billing'),
            _Highlight(Icons.local_shipping_rounded, 'Door delivery'),
          ],
        ),
      ],
    );
  }
}

class _Highlight extends StatelessWidget {
  const _Highlight(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.10),
            Colors.white.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: HomeFooter._cyan.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: HomeFooter._cyan),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkColumn extends StatelessWidget {
  const _LinkColumn({
    required this.title,
    required this.links,
    this.columns = 1,
  });

  final String title;
  final List<(String, VoidCallback)> links;

  /// Lay the links out in this many columns (used for categories on phones).
  final int columns;

  @override
  Widget build(BuildContext context) {
    final items = [for (final (l, f) in links) _FooterLink(l, f)];
    Widget body;
    if (columns <= 1) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items,
      );
    } else {
      final perColumn = (items.length / columns).ceil();
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var c = 0; c < columns; c++) ...[
            if (c > 0) const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: items.skip(c * perColumn).take(perColumn).toList(),
              ),
            ),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        // Cyan accent bar under each heading.
        Container(
          width: 28,
          height: 3,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            gradient: const LinearGradient(
              colors: [HomeFooter._cyan, Color(0xFF3B82F6)],
            ),
            boxShadow: [
              BoxShadow(
                color: HomeFooter._cyan.withValues(alpha: 0.6),
                blurRadius: 6,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        body,
      ],
    );
  }
}

class _FooterLink extends StatefulWidget {
  const _FooterLink(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;

  @override
  State<_FooterLink> createState() => _FooterLinkState();
}

class _FooterLinkState extends State<_FooterLink> {
  bool _active = false;

  void _set(bool v) {
    if (_active != v) setState(() => _active = v);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _set(true),
      onExit: (_) => _set(false),
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 180),
            offset: Offset(_active ? 0.04 : 0, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: _active ? 10 : 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: HomeFooter._cyan.withValues(
                      alpha: _active ? 1 : 0.6,
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 9),
                Flexible(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 180),
                    style: TextStyle(
                      color: _active ? HomeFooter._cyan : HomeFooter._text,
                      fontSize: 13.5,
                      fontFamily: DefaultTextStyle.of(context).style.fontFamily,
                    ),
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
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
