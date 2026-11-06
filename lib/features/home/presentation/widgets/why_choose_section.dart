import 'dart:math' as math;

import 'package:flutter/material.dart';

/// "Why Choose NeeroPlus?" feature section for the Home page.
///
/// Four feature cards with gradient icon tiles inside a slowly turning dashed
/// ring. Icons gently float; cards lift, glow and spin their ring on hover.
/// Desktop: one row of four. Tablet: 2 × 2. Phone: stacked list cards.
class WhyChooseSection extends StatelessWidget {
  const WhyChooseSection({super.key});

  static const cyan = Color(0xFF06B6D4);
  static const blue = Color(0xFF2563EB);
  static const ink = Color(0xFF0F172A);
  static const muted = Color(0xFF64748B);

  static const features = <_Feature>[
    _Feature(
      icon: Icons.bolt_rounded,
      title: 'Lightning Fast Deliveries',
      body: 'Express dispatch within 24 hours, delivered to your door.',
      tag: 'EXPRESS DISPATCH',
    ),
    _Feature(
      icon: Icons.verified_user_rounded,
      title: '100% Genuine Products',
      body: 'Authentic RO purifiers, membranes, filters and spare parts.',
      tag: 'GENUINE',
    ),
    _Feature(
      icon: Icons.payments_rounded,
      title: 'Pay on Delivery',
      body: 'Cash on delivery, or pay online with UPI, cards and net banking.',
      tag: 'COD',
    ),
    _Feature(
      icon: Icons.local_offer_rounded,
      title: 'Bulk Order Savings',
      body: 'Dealer prices with volume discounts on every wholesale order.',
      tag: 'BEST DEALS',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final desktop = w >= 960;
        final tablet = w >= 560 && !desktop;

        Widget grid;
        if (desktop) {
          grid = IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < features.length; i++) ...[
                  if (i > 0) const SizedBox(width: 20),
                  Expanded(child: _FeatureCard(features[i], index: i)),
                ],
              ],
            ),
          );
        } else if (tablet) {
          Widget pair(int a) => IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _FeatureCard(features[a], index: a)),
                const SizedBox(width: 16),
                Expanded(child: _FeatureCard(features[a + 1], index: a + 1)),
              ],
            ),
          );
          grid = Column(
            children: [pair(0), const SizedBox(height: 16), pair(2)],
          );
        } else {
          grid = Column(
            children: [
              for (var i = 0; i < features.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                _FeatureCard(features[i], index: i, horizontal: true),
              ],
            ],
          );
        }

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: EdgeInsets.fromLTRB(
            desktop ? 36 : 18,
            desktop ? 44 : 30,
            desktop ? 36 : 18,
            desktop ? 44 : 24,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(desktop ? 32 : 24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? const [Color(0xFF0F2236), Color(0xFF0B1A2B)]
                  : const [Color(0xFFE9FAFF), Color(0xFFF7FBFF), Colors.white],
            ),
            border: Border.all(
              color: isDark
                  ? Colors.white10
                  : const Color(0xFFD7F1FA).withValues(alpha: 0.9),
            ),
          ),
          child: Column(
            children: [
              Text(
                'THE NEEROPLUS ADVANTAGE',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cyan,
                  fontSize: desktop ? 13 : 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Why Choose NeeroPlus?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.white : ink,
                  fontSize: desktop ? 40 : 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: desktop ? 110 : 80,
                height: 5,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: const LinearGradient(colors: [cyan, blue]),
                ),
              ),
              SizedBox(height: desktop ? 40 : 26),
              grid,
            ],
          ),
        );
      },
    );
  }
}

class _Feature {
  const _Feature({
    required this.icon,
    required this.title,
    required this.body,
    required this.tag,
  });

  final IconData icon;
  final String title;
  final String body;
  final String tag;
}

class _FeatureCard extends StatefulWidget {
  const _FeatureCard(
    this.feature, {
    required this.index,
    this.horizontal = false,
  });

  final _Feature feature;
  final int index;

  /// Phone layout: icon on the left, text on the right.
  final bool horizontal;

  @override
  State<_FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<_FeatureCard>
    with SingleTickerProviderStateMixin {
  bool _hovered = false;

  // Drives the icon float and the dashed ring rotation.
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
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
      // Stagger cards so they don't bob in unison.
      _loop.value = widget.index / 4;
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final f = widget.feature;
    final horizontal = widget.horizontal;

    final icon = _IconTile(
      icon: f.icon,
      loop: _loop,
      hovered: _hovered,
      size: horizontal ? 72 : 112,
    );
    final title = Text(
      f.title,
      textAlign: horizontal ? TextAlign.left : TextAlign.center,
      style: TextStyle(
        color: isDark ? Colors.white : WhyChooseSection.ink,
        fontSize: horizontal ? 16 : 19,
        fontWeight: FontWeight.w800,
        height: 1.25,
        letterSpacing: -0.3,
      ),
    );
    final body = Text(
      f.body,
      textAlign: horizontal ? TextAlign.left : TextAlign.center,
      style: TextStyle(
        color: isDark ? Colors.white60 : WhyChooseSection.muted,
        fontSize: 13,
        height: 1.5,
      ),
    );
    final tag = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: WhyChooseSection.cyan.withValues(alpha: isDark ? 0.18 : 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        f.tag,
        style: const TextStyle(
          color: Color(0xFF0891B2),
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.4,
        ),
      ),
    );

    final content = horizontal
        ? Row(
            children: [
              icon,
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    const SizedBox(height: 4),
                    body,
                    const SizedBox(height: 8),
                    tag,
                  ],
                ),
              ),
            ],
          )
        : Column(
            children: [
              icon,
              const SizedBox(height: 22),
              title,
              const SizedBox(height: 8),
              body,
              const Spacer(),
              const SizedBox(height: 16),
              tag,
            ],
          );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _hovered ? -6 : 0, 0),
        padding: EdgeInsets.all(horizontal ? 14 : 24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF132233) : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: _hovered
                ? WhyChooseSection.cyan.withValues(alpha: 0.45)
                : (isDark ? Colors.white10 : const Color(0xFFE3F2F8)),
          ),
          boxShadow: [
            BoxShadow(
              color:
                  (_hovered ? WhyChooseSection.cyan : const Color(0xFF0F2850))
                      .withValues(alpha: _hovered ? 0.18 : 0.05),
              blurRadius: _hovered ? 30 : 14,
              offset: Offset(0, _hovered ? 14 : 5),
            ),
          ],
        ),
        child: content,
      ),
    );
  }
}

/// Gradient icon tile inside a dashed ring that slowly turns.
class _IconTile extends StatelessWidget {
  const _IconTile({
    required this.icon,
    required this.loop,
    required this.hovered,
    required this.size,
  });

  final IconData icon;
  final Animation<double> loop;
  final bool hovered;
  final double size;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tile = size * 0.68;
    return SizedBox(
      width: size,
      height: size,
      child: AnimatedBuilder(
        animation: loop,
        builder: (context, _) {
          final t = loop.value;
          final float = math.sin(t * math.pi * 2) * size * 0.03;
          return Stack(
            alignment: Alignment.center,
            children: [
              // Soft halo + dashed ring.
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : const Color(0xFFF2FBFE),
                  borderRadius: BorderRadius.circular(size * 0.3),
                ),
              ),
              Transform.rotate(
                angle: t * math.pi * 2 * (hovered ? 2 : 1) * 0.25,
                child: CustomPaint(
                  size: Size.square(size * 0.9),
                  painter: _DashedRingPainter(
                    color: WhyChooseSection.cyan.withValues(
                      alpha: hovered ? 0.6 : 0.3,
                    ),
                    radius: size * 0.27,
                  ),
                ),
              ),
              Transform.translate(
                offset: Offset(0, float),
                child: AnimatedScale(
                  scale: hovered ? 1.08 : 1,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutBack,
                  child: Container(
                    width: tile,
                    height: tile,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(tile * 0.26),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF22D3EE), Color(0xFF0EA5E9)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: WhyChooseSection.cyan.withValues(
                            alpha: hovered ? 0.5 : 0.3,
                          ),
                          blurRadius: hovered ? 22 : 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Icon(icon, color: Colors.white, size: tile * 0.52),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DashedRingPainter extends CustomPainter {
  _DashedRingPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      const dash = 6.0, gap = 5.0;
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRingPainter old) =>
      old.color != color || old.radius != radius;
}
