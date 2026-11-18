import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'hero_slides.dart';

/// Where the product (and its podium) sit, as fractions of the slide size.
@immutable
class HeroStage {
  const HeroStage({
    required this.centerX,
    required this.podiumY,
    required this.podiumWidth,
  });

  /// Horizontal centre of the product / podium.
  final double centerX;

  /// Vertical centre of the podium's top face.
  final double podiumY;

  /// Podium width as a fraction of the slide width.
  final double podiumWidth;
}

/// Animated slide background: gradient, soft lighting, decorative circles,
/// bokeh, a water surface with ripples, the podium and (optionally) splash
/// droplets. Drawn behind the product.
class HeroBackdrop extends StatelessWidget {
  const HeroBackdrop({
    super.key,
    required this.slide,
    required this.stage,
    required this.loop,
  });

  final HeroSlide slide;
  final HeroStage stage;
  final Animation<double> loop;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _BackdropPainter(slide: slide, stage: stage, t: loop),
    ),
  );
}

/// Leaves drawn in front of the product (corner foliage, podium sprigs).
class HeroForeground extends StatelessWidget {
  const HeroForeground({
    super.key,
    required this.slide,
    required this.stage,
    required this.loop,
  });

  final HeroSlide slide;
  final HeroStage stage;
  final Animation<double> loop;

  @override
  Widget build(BuildContext context) {
    if (slide.leaves == HeroLeaves.none) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _LeavesPainter(slide: slide, stage: stage, t: loop),
        ),
      ),
    );
  }
}

const _tau = math.pi * 2;

void _glow(Canvas c, Offset o, double r, Color color, double alpha) {
  if (r <= 0) return;
  c.drawCircle(
    o,
    r,
    Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: alpha),
          color.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: o, radius: r)),
  );
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter({required this.slide, required this.stage, required this.t})
    : super(repaint: t);

  final HeroSlide slide;
  final HeroStage stage;
  final Animation<double> t;

  // Deterministic bokeh field: x, y, radius factor, speed, phase.
  static const _bokeh = <(double, double, double, int, double)>[
    (0.10, 0.18, 0.020, 1, 0.0),
    (0.32, 0.10, 0.012, 2, 0.3),
    (0.46, 0.30, 0.016, 1, 0.6),
    (0.60, 0.12, 0.010, 2, 0.2),
    (0.90, 0.36, 0.018, 1, 0.8),
    (0.20, 0.58, 0.010, 2, 0.5),
    (0.52, 0.62, 0.012, 1, 0.9),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (w <= 0 || h <= 0) return;
    final v = t.value;
    final s = math.sin(v * _tau);
    final rect = Offset.zero & size;
    final dark = slide.dark;
    final cx = w * stage.centerX;
    final py = h * stage.podiumY;
    final pw = w * stage.podiumWidth;

    // 1. Rich base gradient.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: slide.colors,
          stops: const [0, 0.5, 1],
        ).createShader(rect),
    );

    // 2. Soft lighting: a large key light behind the product, a cool fill
    //    light at the top-left.
    _glow(
      canvas,
      Offset(cx, h * (0.36 + 0.02 * s)),
      h * 0.78,
      Colors.white,
      dark ? 0.30 : 0.75,
    );
    _glow(
      canvas,
      Offset(w * 0.08, h * 0.02),
      h * 0.55,
      Colors.white,
      dark ? 0.10 : 0.55,
    );

    // 3. Decorative circles (thin rings + faint discs).
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = Colors.white.withValues(alpha: dark ? 0.16 : 0.55);
    canvas.drawCircle(Offset(w * 1.02, h * -0.02), h * 0.36, ring);
    canvas.drawCircle(
      Offset(w * 1.02, h * -0.02),
      h * 0.46,
      ring..color = Colors.white.withValues(alpha: dark ? 0.08 : 0.35),
    );
    canvas.drawCircle(
      Offset(w * -0.04, h * 1.02),
      h * 0.30,
      Paint()..color = Colors.white.withValues(alpha: dark ? 0.05 : 0.30),
    );
    canvas.drawCircle(
      Offset(w * -0.04, h * 1.02),
      h * 0.38,
      ring..color = Colors.white.withValues(alpha: dark ? 0.10 : 0.45),
    );

    // 4. Bokeh drifting slowly upwards.
    for (final (bx, by, br, speed, phase) in _bokeh) {
      final q = (v * speed + phase) % 1.0;
      final o = Offset(
        w * bx + math.sin((q + phase) * _tau) * 6,
        h * by - q * h * 0.08,
      );
      _glow(
        canvas,
        o,
        h * br * 2.2,
        Colors.white,
        (dark ? 0.35 : 0.8) * math.sin(q * math.pi),
      );
    }

    // 5. Water surface along the bottom.
    final waterTop = py - h * 0.04;
    final water = Rect.fromLTRB(0, waterTop, w, h);
    canvas.drawRect(
      water,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? [
                  Colors.white.withValues(alpha: 0),
                  const Color(0xFF7FD3FF).withValues(alpha: 0.22),
                  Colors.white.withValues(alpha: 0.10),
                ]
              : [
                  Colors.white.withValues(alpha: 0),
                  Colors.white.withValues(alpha: 0.55),
                  const Color(0xFF8FD3F0).withValues(alpha: 0.35),
                ],
          stops: const [0, 0.45, 1],
        ).createShader(water),
    );
    // Shimmering light streaks on the water.
    final streak = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < 6; i++) {
      final y = waterTop + (h - waterTop) * (0.25 + i * 0.13);
      final x = w * ((0.08 + i * 0.17 + v * (i.isEven ? 0.05 : -0.05)) % 1.0);
      streak
        ..strokeWidth = 1.6
        ..color = Colors.white.withValues(alpha: dark ? 0.25 : 0.7);
      canvas.drawLine(Offset(x, y), Offset(x + w * 0.06, y), streak);
    }

    // 6. Ripples spreading from the podium base.
    final base = Offset(cx, py + pw * 0.16);
    final rp = Paint()..style = PaintingStyle.stroke;
    for (var i = 0; i < 4; i++) {
      final q = (v * 2 + i / 4) % 1.0;
      final rw = pw * (1.05 + 1.1 * q);
      rp
        ..strokeWidth = 1.6 * (1 - q) + 0.4
        ..color = Colors.white.withValues(
          alpha: (1 - q) * (dark ? 0.45 : 0.85),
        );
      canvas.drawOval(
        Rect.fromCenter(center: base, width: rw, height: rw * 0.20),
        rp,
      );
    }

    // 7. Podium.
    _podium(canvas, Offset(cx, py), pw, dark);

    // 8. Splash droplets either side of the podium.
    if (slide.splash) _splash(canvas, Offset(cx, py), pw, v);
  }

  void _podium(Canvas canvas, Offset c, double pw, bool dark) {
    final topH = pw * 0.20;
    final sideH = pw * 0.13;
    final top = Rect.fromCenter(center: c, width: pw, height: topH);
    final bottom = top.shift(Offset(0, sideH));

    // Reflection glow on the water under the podium.
    _glow(
      canvas,
      bottom.center + Offset(0, topH * 0.4),
      pw * 0.62,
      Colors.white,
      dark ? 0.25 : 0.55,
    );

    final (
      List<Color> side,
      List<Color> face,
      Color rim,
    ) = switch (slide.podium) {
      HeroPodium.blue => (
        [const Color(0xFF2B7FE0), const Color(0xFF0B3C8C)],
        [const Color(0xFFE8F7FF), const Color(0xFF6DB8F2)],
        const Color(0xFFDFF4FF),
      ),
      HeroPodium.stone => (
        [const Color(0xFFE3E6E4), const Color(0xFF9AA39F)],
        [const Color(0xFFFFFFFF), const Color(0xFFCFD5D2)],
        Colors.white,
      ),
      HeroPodium.glass => (
        [Colors.white.withValues(alpha: 0.95), const Color(0xFFC9E2F5)],
        [Colors.white, const Color(0xFFE4F1FB)],
        Colors.white,
      ),
    };

    // Side band (cylinder wall).
    final wall = Path()
      ..moveTo(top.left, c.dy)
      ..lineTo(bottom.left, bottom.center.dy)
      ..arcTo(bottom, math.pi, -math.pi, false)
      ..lineTo(top.right, c.dy)
      ..arcTo(top, 0, math.pi, false)
      ..close();
    canvas.drawPath(
      wall,
      Paint()
        ..shader =
            LinearGradient(
              colors: [side[1], side[0], side[0], side[1]],
              stops: const [0, 0.35, 0.6, 1],
            ).createShader(
              Rect.fromLTRB(top.left, top.top, top.right, bottom.bottom),
            ),
    );

    // Top face.
    canvas.drawOval(
      top,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.2, -0.4),
          radius: 0.9,
          colors: face,
        ).createShader(top),
    );
    if (slide.podium == HeroPodium.stone) {
      // Subtle stone speckle.
      final speck = Paint()
        ..color = const Color(0xFF8D9692).withValues(alpha: 0.25);
      final rnd = math.Random(7);
      for (var i = 0; i < 40; i++) {
        final a = rnd.nextDouble() * _tau;
        final r = math.sqrt(rnd.nextDouble());
        canvas.drawCircle(
          Offset(
            c.dx + math.cos(a) * r * pw * 0.46,
            c.dy + math.sin(a) * r * topH * 0.42,
          ),
          0.9 + rnd.nextDouble(),
          speck,
        );
      }
    }
    // Glossy rim.
    canvas.drawOval(
      top.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = rim.withValues(alpha: 0.9),
    );
    // Contact shadow where the product stands.
    final shadow = Rect.fromCenter(
      center: c.translate(0, -topH * 0.05),
      width: pw * 0.62,
      height: topH * 0.45,
    );
    canvas.drawOval(
      shadow,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.black.withValues(alpha: 0.22),
            Colors.black.withValues(alpha: 0),
          ],
        ).createShader(shadow),
    );
  }

  void _splash(Canvas canvas, Offset c, double pw, double v) {
    final drop = Paint();
    final shine = Paint()..color = Colors.white.withValues(alpha: 0.9);
    for (final side in [-1.0, 1.0]) {
      for (var i = 0; i < 9; i++) {
        final f = i / 8; // along the arc
        final bob = math.sin((v * 3 + f + side) * _tau) * 3;
        final x = c.dx + side * pw * (0.50 + f * 0.16);
        final y = c.dy - pw * (0.05 + math.sin(f * math.pi) * 0.22) + bob;
        final r = 1.6 + (1 - f) * 2.6;
        drop.color = Colors.white.withValues(alpha: 0.55 + 0.3 * (1 - f));
        canvas.drawCircle(Offset(x, y), r, drop);
        canvas.drawCircle(Offset(x - r * 0.3, y - r * 0.3), r * 0.35, shine);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter old) =>
      old.slide != slide || old.stage != stage;
}

class _LeavesPainter extends CustomPainter {
  _LeavesPainter({required this.slide, required this.stage, required this.t})
    : super(repaint: t);

  final HeroSlide slide;
  final HeroStage stage;
  final Animation<double> t;

  // x, y (fractions), length (fraction of height), angle (0 = up, π = down).
  static const _corner = <(double, double, double, double)>[
    (0.98, -0.03, 0.30, 3.75),
    (0.90, -0.05, 0.26, 3.30),
    (0.82, -0.04, 0.20, 2.85),
    (1.02, 0.14, 0.24, 4.30),
  ];
  static const _accentCorner = <(double, double, double, double)>[
    (0.97, -0.04, 0.18, 3.55),
    (0.90, -0.05, 0.13, 3.05),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (w <= 0 || h <= 0) return;
    final v = t.value;
    final lush = slide.leaves == HeroLeaves.lush;

    final leaves = [
      ...(lush ? _corner : _accentCorner),
      // Sprigs at the podium base.
      (
        stage.centerX - stage.podiumWidth * 0.52,
        stage.podiumY + 0.10,
        lush ? 0.20 : 0.15,
        -0.75,
      ),
      if (lush)
        (
          stage.centerX + stage.podiumWidth * 0.52,
          stage.podiumY + 0.08,
          0.17,
          0.80,
        ),
    ];

    for (var i = 0; i < leaves.length; i++) {
      final (x, y, len, angle) = leaves[i];
      final sway = math.sin((v * 2 + i * 0.37) * _tau) * 0.05;
      _leaf(canvas, Offset(w * x, h * y), h * len, angle + sway, i);
    }
  }

  void _leaf(Canvas canvas, Offset base, double length, double angle, int i) {
    final width = length * 0.36;
    canvas.save();
    canvas.translate(base.dx, base.dy);
    canvas.rotate(angle);
    final path = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(width, -length * 0.45, 0, -length)
      ..quadraticBezierTo(-width * 0.85, -length * 0.5, 0, 0)
      ..close();
    final bounds = Rect.fromLTRB(-width, -length, width, 0);
    // Soft drop shadow.
    canvas.drawPath(
      path.shift(const Offset(3, 4)),
      Paint()
        ..color = const Color(0xFF0B3D1B).withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    final dark = i.isEven ? const Color(0xFF1E7A34) : const Color(0xFF2E8B3E);
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [dark, const Color(0xFF6CC24A), const Color(0xFF9BDC6E)],
          stops: const [0, 0.6, 1],
        ).createShader(bounds),
    );
    // Midrib and a few veins.
    final vein = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = Colors.white.withValues(alpha: 0.45);
    canvas.drawLine(Offset.zero, Offset(0, -length * 0.92), vein);
    vein.strokeWidth = 0.7;
    for (var k = 1; k <= 4; k++) {
      final y = -length * (0.18 + k * 0.16);
      canvas.drawLine(
        Offset(0, y),
        Offset(width * 0.45, y - length * 0.08),
        vein,
      );
      canvas.drawLine(
        Offset(0, y),
        Offset(-width * 0.38, y - length * 0.08),
        vein,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LeavesPainter old) =>
      old.slide != slide || old.stage != stage;
}
