import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Animated water-themed backdrop for the home carousel banners.
///
/// Layers (back to front): drifting gradient, soft glow orbs, a pulsing halo
/// with expanding ripples behind the product, rising bubbles, a slow light
/// sweep and three layered flowing waves along the bottom.
///
/// All motion loops seamlessly and stops when the platform asks for reduced
/// motion (MediaQuery.disableAnimations).
class AnimatedBannerBackground extends StatefulWidget {
  const AnimatedBannerBackground({
    super.key,
    required this.gradient,
    required this.accentColor,
    required this.isDark,
    this.keepGradientInDark = false,
  });

  final LinearGradient gradient;
  final Color accentColor;

  /// Uses the subtler dark-surface effects (for deep-coloured banners).
  final bool isDark;

  /// Paint [gradient] even when [isDark] is set, instead of the default
  /// navy dark-mode backdrop.
  final bool keepGradientInDark;

  @override
  State<AnimatedBannerBackground> createState() =>
      _AnimatedBannerBackgroundState();
}

class _AnimatedBannerBackgroundState extends State<AnimatedBannerBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_shouldAnimate(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _BannerBackdropPainter(
          animation: _controller,
          gradient: widget.gradient,
          accent: widget.accentColor,
          isDark: widget.isDark,
          keepGradientInDark: widget.keepGradientInDark,
        ),
      ),
    );
  }
}

/// Gentle up-and-down float for the banner product image.
class FloatingBannerProduct extends StatefulWidget {
  const FloatingBannerProduct({super.key, required this.child});

  final Widget child;

  @override
  State<FloatingBannerProduct> createState() => _FloatingBannerProductState();
}

class _FloatingBannerProductState extends State<FloatingBannerProduct>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_shouldAnimate(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOutSine.transform(_controller.value);
        return Transform.translate(offset: Offset(0, 5 - 10 * t), child: child);
      },
      child: widget.child,
    );
  }
}

class _BannerBackdropPainter extends CustomPainter {
  _BannerBackdropPainter({
    required this.animation,
    required this.gradient,
    required this.accent,
    required this.isDark,
    this.keepGradientInDark = false,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final LinearGradient gradient;
  final Color accent;
  final bool isDark;
  final bool keepGradientInDark;

  static const _tau = math.pi * 2;

  // Deterministic bubble field: (x fraction, radius, speed, phase).
  static const _bubbles = <(double, double, double, double)>[
    (0.56, 4.0, 1, 0.00),
    (0.63, 6.5, 2, 0.35),
    (0.70, 3.5, 1, 0.62),
    (0.78, 5.0, 2, 0.15),
    (0.86, 3.0, 1, 0.80),
    (0.93, 5.5, 1, 0.45),
    (0.40, 3.0, 1, 0.25),
    (0.48, 4.5, 2, 0.70),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;
    final t = animation.value; // 0..1, loops seamlessly
    final rect = Offset.zero & size;

    // 1. Base gradient with a slow, subtle sway of its angle.
    final base = isDark && !keepGradientInDark
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0E1E30), Color(0xFF15304D), Color(0xFF1B3D63)],
          )
        : gradient;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: base.begin,
          end: base.end,
          colors: base.colors,
          stops: base.stops,
          transform: GradientRotation(math.sin(t * _tau) * 0.18),
        ).createShader(rect),
    );

    // 2. Soft glow orbs drifting on slow loops.
    void orb(Offset c, double r, Color color, double alpha) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    orb(
      Offset(
        w * (0.18 + 0.06 * math.sin(t * _tau)),
        h * (0.10 + 0.08 * math.cos(t * _tau)),
      ),
      h * 0.9,
      Colors.white,
      isDark ? 0.06 : 0.45,
    );
    orb(
      Offset(
        w * (0.45 + 0.08 * math.cos(t * _tau)),
        h * (1.05 + 0.06 * math.sin(t * _tau * 2)),
      ),
      h * 0.8,
      accent,
      isDark ? 0.22 : 0.22,
    );

    // 3. Pulsing halo + expanding water ripples behind the product.
    final halo = Offset(w * 0.78, h * 0.50);
    final pulse = 0.5 + 0.5 * math.sin(t * _tau * 3);
    orb(
      halo,
      h * (0.62 + 0.05 * pulse),
      Colors.white,
      isDark ? 0.10 : 0.55 + 0.15 * pulse,
    );
    orb(halo, h * 0.46, accent, isDark ? 0.18 : 0.14);

    final ripple = Paint()..style = PaintingStyle.stroke;
    for (var i = 0; i < 3; i++) {
      final p = (t * 3 + i / 3) % 1.0; // three rings, staggered
      ripple
        ..strokeWidth = 1.6 * (1 - p) + 0.4
        ..color = (isDark ? Colors.white : accent).withValues(
          alpha: (1 - p) * (isDark ? 0.16 : 0.28),
        );
      canvas.drawCircle(halo, h * (0.30 + 0.75 * p), ripple);
    }

    // 4. Rising bubbles with specular highlights.
    final bubbleFill = Paint();
    final bubbleRim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final shine = Paint()..color = Colors.white.withValues(alpha: 0.9);
    for (final (fx, r, speed, phase) in _bubbles) {
      final p = (t * speed + phase) % 1.0;
      final y = h * 1.05 - p * h * 1.15;
      final x = w * fx + math.sin((p + phase) * _tau * 2) * 6;
      final fade = math.sin(p * math.pi); // fade in at bottom, out at top
      final c = Offset(x, y);
      bubbleFill.color = Colors.white.withValues(alpha: 0.28 * fade);
      bubbleRim.color = accent.withValues(alpha: 0.45 * fade);
      canvas.drawCircle(c, r, bubbleFill);
      canvas.drawCircle(c, r, bubbleRim);
      shine.color = Colors.white.withValues(alpha: 0.9 * fade);
      canvas.drawCircle(Offset(x - r * 0.35, y - r * 0.35), r * 0.28, shine);
    }

    // 5. Slow diagonal light sweep (glass sheen) crossing once per loop.
    final sweepX = -w * 0.4 + (w * 1.8) * t;
    canvas.save();
    canvas.translate(sweepX, 0);
    canvas.skew(-0.35, 0);
    final sweepRect = Rect.fromLTWH(0, 0, w * 0.18, h);
    canvas.drawRect(
      sweepRect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: isDark ? 0.05 : 0.22),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(sweepRect),
    );
    canvas.restore();

    // 6. Three layered flowing waves along the bottom (back to front).
    void wave({
      required double baseY,
      required double amp,
      required double cycles,
      required double speed,
      required double alpha,
      bool crest = false,
    }) {
      final phase = t * _tau * speed;
      final path = Path()..moveTo(0, h);
      const steps = 48;
      for (var i = 0; i <= steps; i++) {
        final x = w * i / steps;
        final y =
            h * baseY +
            math.sin((i / steps) * _tau * cycles + phase) * amp +
            math.sin((i / steps) * _tau * cycles * 2.1 - phase) * amp * 0.3;
        path.lineTo(x, y);
      }
      path
        ..lineTo(w, h)
        ..close();
      final top = h * baseY - amp;
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              accent.withValues(alpha: alpha),
              accent.withValues(alpha: alpha * 1.6),
            ],
          ).createShader(Rect.fromLTRB(0, top, w, h)),
      );
      if (crest) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = Colors.white.withValues(alpha: isDark ? 0.12 : 0.55),
        );
      }
    }

    wave(baseY: 0.78, amp: h * 0.035, cycles: 1.2, speed: 1, alpha: 0.07);
    wave(baseY: 0.84, amp: h * 0.030, cycles: 1.7, speed: -2, alpha: 0.09);
    wave(
      baseY: 0.90,
      amp: h * 0.022,
      cycles: 2.3,
      speed: 3,
      alpha: 0.12,
      crest: true,
    );
  }

  @override
  bool shouldRepaint(covariant _BannerBackdropPainter old) =>
      old.gradient != gradient || old.accent != accent || old.isDark != isDark;
}

/// Looping decoration should run in the app, but not when the platform asks
/// for reduced motion, and not under widget tests (where an endless animation
/// would make `pumpAndSettle` time out). The test binding is not a
/// [WidgetsFlutterBinding], which is how the two are told apart.
bool _shouldAnimate(BuildContext context) =>
    !MediaQuery.disableAnimationsOf(context) &&
    WidgetsBinding.instance is WidgetsFlutterBinding;
