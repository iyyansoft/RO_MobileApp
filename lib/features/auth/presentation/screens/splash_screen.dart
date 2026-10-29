import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _animationController;
  late final AnimationController _waterController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _waterController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat();
    _scaleAnimation = Tween<double>(begin: .82, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );
    _animationController.forward();
    _prepareAndNavigate();
  }

  Future<void> _prepareAndNavigate() async {
    await Future.wait([
      Future<void>.delayed(const Duration(milliseconds: 900)),
      ref.read(authProvider.notifier).restoreSession(),
    ]);
    if (mounted) {
      context.go(ref.read(authProvider).isLoggedIn ? '/home' : '/login');
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _waterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4FBFF),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // The source logo has transparent top/bottom padding. Size it by
          // width and preserve its full canvas so it is never cropped.
          final availableLogoHeight = math.max(
            0.0,
            constraints.maxHeight - 194.0,
          );
          final logoWidth = math
              .min(
                math.min(constraints.maxWidth * .74, availableLogoHeight),
                480.0,
              )
              .toDouble();
          return Stack(
            fit: StackFit.expand,
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFFFFFFFF),
                      Color(0xFFF5FBFF),
                      Color(0xFFE8F7FF),
                    ],
                    stops: [0, .56, 1],
                  ),
                ),
              ),
              IgnorePointer(
                child: CustomPaint(
                  painter: _WaterBackgroundPainter(_waterController),
                ),
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 76),
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: ScaleTransition(
                      scale: _scaleAnimation,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: logoWidth,
                            child: Image.asset(
                              'assets/images/RO_LOGO.png',
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                              semanticLabel: 'Neero water logo',
                            ),
                          ),
                          const SizedBox(height: 22),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 24),
                            child: Text(
                              'Aqua Tech Solutions • B2B Dealer Portal',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF31577F),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: .35,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Color(0xFF1686D9),
                              ),
                            ),
                          ),
                          const SizedBox(height: 9),
                          const Text(
                            'Loading Secure Dealer Session...',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF54718E),
                              fontWeight: FontWeight.w500,
                              letterSpacing: .15,
                            ),
                          ),
                        ],
                      ),
                    ),
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

class _WaterBackgroundPainter extends CustomPainter {
  _WaterBackgroundPainter(this.animation) : super(repaint: animation);

  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    final phase = animation.value * math.pi * 2;
    _drawWave(
      canvas,
      size,
      base: size.height * .78,
      amplitude: 19,
      phase: phase,
      colors: const [Color(0xFFCDEFFF), Color(0xFFEAF8FF)],
    );
    _drawWave(
      canvas,
      size,
      base: size.height * .84,
      amplitude: 23,
      phase: phase + 1.2,
      colors: const [Color(0xFF9FE0FA), Color(0xFFDDF5FF)],
    );
    _drawWave(
      canvas,
      size,
      base: size.height * .92,
      amplitude: 18,
      phase: phase + 2.4,
      colors: const [Color(0xFF71C7EE), Color(0xFFB9E9FA)],
    );

    final bubbles = <(double, double, double, double)>[
      (.07, .25, 8, .1),
      (.14, .46, 4, 1.2),
      (.05, .65, 6, 2.4),
      (.93, .22, 5, .6),
      (.88, .42, 8, 1.8),
      (.96, .63, 4, 2.8),
      (.2, .7, 3, 1.4),
      (.82, .72, 3, .4),
    ];
    final bubblePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = const Color(0xFF4CAFE3).withValues(alpha: .28);
    for (final bubble in bubbles) {
      final lift = math.sin(phase + bubble.$4) * 6;
      final center = Offset(
        size.width * bubble.$1,
        size.height * bubble.$2 - lift,
      );
      canvas.drawCircle(center, bubble.$3, bubblePaint);
      canvas.drawCircle(
        center.translate(-bubble.$3 * .25, -bubble.$3 * .25),
        bubble.$3 * .22,
        Paint()..color = const Color(0xFF4CAFE3).withValues(alpha: .18),
      );
    }
  }

  void _drawWave(
    Canvas canvas,
    Size size, {
    required double base,
    required double amplitude,
    required double phase,
    required List<Color> colors,
  }) {
    final shift = math.sin(phase) * 12;
    final path = Path()
      ..moveTo(0, base + math.sin(phase) * amplitude)
      ..cubicTo(
        size.width * .22,
        base - amplitude + shift,
        size.width * .38,
        base + amplitude - shift,
        size.width * .58,
        base + math.sin(phase + 1) * amplitude,
      )
      ..cubicTo(
        size.width * .78,
        base - amplitude - shift,
        size.width * .9,
        base + amplitude + shift,
        size.width,
        base + math.sin(phase + 2) * amplitude,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    final rect = Rect.fromLTWH(0, base - amplitude, size.width, size.height);
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
        ).createShader(rect),
    );
    final highlight = Path()
      ..moveTo(0, base + math.sin(phase) * amplitude)
      ..cubicTo(
        size.width * .22,
        base - amplitude + shift,
        size.width * .38,
        base + amplitude - shift,
        size.width * .58,
        base + math.sin(phase + 1) * amplitude,
      )
      ..cubicTo(
        size.width * .78,
        base - amplitude - shift,
        size.width * .9,
        base + amplitude + shift,
        size.width,
        base + math.sin(phase + 2) * amplitude,
      );
    canvas.drawPath(
      highlight,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: .45),
    );
  }

  @override
  bool shouldRepaint(covariant _WaterBackgroundPainter oldDelegate) =>
      oldDelegate.animation != animation;
}
