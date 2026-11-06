import 'package:flutter/material.dart';

import 'animated_banner_background.dart';

/// Full-width "Exclusive Wholesale Partnership" promo on the Home page.
///
/// Deep navy animated water backdrop, gradient headline, feature chips, a
/// compact glowing CTA and a floating product duo on a glowing platform.
class WholesalePromoBanner extends StatelessWidget {
  const WholesalePromoBanner({
    super.key,
    required this.isDesktop,
    required this.onExplore,
  });

  final bool isDesktop;
  final VoidCallback onExplore;

  static const _cyan = Color(0xFF22D3EE);
  static const _mint = Color(0xFF2EF2C8);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final height = wide ? 270.0 : 236.0;
        final radius = BorderRadius.circular(wide ? 28 : 22);

        return Container(
          height: height,
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0369A1).withValues(alpha: 0.35),
                blurRadius: 34,
                spreadRadius: -8,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const AnimatedBannerBackground(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF061A33),
                      Color(0xFF0B3A6E),
                      Color(0xFF0E7FC0),
                    ],
                    stops: [0, 0.55, 1],
                  ),
                  accentColor: _cyan,
                  isDark: true,
                  keepGradientInDark: true,
                ),
                // Thin glass border on top of everything.
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    wide ? 40 : 18,
                    wide ? 26 : 16,
                    wide ? 24 : 10,
                    wide ? 26 : 16,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: wide ? 58 : 60,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: wide ? 620 : 340,
                            ),
                            child: _Copy(wide: wide, onExplore: onExplore),
                          ),
                        ),
                      ),
                      SizedBox(width: wide ? 16 : 6),
                      Expanded(
                        flex: wide ? 42 : 40,
                        child: _ProductShowcase(wide: wide),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Copy extends StatelessWidget {
  const _Copy({required this.wide, required this.onExplore});

  final bool wide;
  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: WholesalePromoBanner._cyan.withValues(alpha: 0.45),
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.workspace_premium_rounded,
                size: 13,
                color: WholesalePromoBanner._mint,
              ),
              SizedBox(width: 6),
              Flexible(
                child: Text(
                  'EXCLUSIVE WHOLESALE PARTNERSHIP',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xFFE0F2FE),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: wide ? 14 : 10),
        // Headline with a white → cyan gradient on the second line.
        Text(
          'High TDS Membranes',
          style: TextStyle(
            color: Colors.white,
            fontSize: wide ? 32 : 21,
            fontWeight: FontWeight.w900,
            height: 1.08,
            letterSpacing: -0.6,
          ),
        ),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFF7DD3FC), WholesalePromoBanner._mint],
          ).createShader(bounds),
          child: Text(
            '& Commercial Spares',
            style: TextStyle(
              fontSize: wide ? 32 : 21,
              fontWeight: FontWeight.w900,
              height: 1.12,
              letterSpacing: -0.6,
            ),
          ),
        ),
        SizedBox(height: wide ? 14 : 10),
        // Feature chips (from the original description).
        const Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _FeatureChip(Icons.local_offer_rounded, 'Volume discounts'),
            _FeatureChip(Icons.receipt_long_rounded, 'Instant GST billing'),
            _FeatureChip(Icons.local_shipping_rounded, 'Door delivery'),
          ],
        ),
        SizedBox(height: wide ? 20 : 14),
        _GlowButton(label: 'Explore Wholesale Deals', onTap: onExplore),
      ],
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: WholesalePromoBanner._cyan),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFDBEAFE),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowButton extends StatefulWidget {
  const _GlowButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_GlowButton> createState() => _GlowButtonState();
}

class _GlowButtonState extends State<_GlowButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.fromLTRB(20, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: const LinearGradient(
              colors: [WholesalePromoBanner._mint, WholesalePromoBanner._cyan],
            ),
            boxShadow: [
              BoxShadow(
                color: WholesalePromoBanner._mint.withValues(
                  alpha: _hovered ? 0.55 : 0.32,
                ),
                blurRadius: _hovered ? 26 : 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF062A4A),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 26,
                height: 26,
                transform: Matrix4.translationValues(_hovered ? 3 : 0, 0, 0),
                decoration: const BoxDecoration(
                  color: Color(0xFF062A4A),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_forward_rounded,
                  size: 15,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Membrane + spare-parts cut-outs floating above a glowing platform.
class _ProductShowcase extends StatelessWidget {
  const _ProductShowcase({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = c.maxHeight;
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // Glow + platform ellipse.
            Positioned(
              bottom: h * 0.04,
              child: Container(
                width: w * 0.86,
                height: h * 0.16,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.all(
                    Radius.elliptical(w * 0.43, h * 0.08),
                  ),
                  gradient: RadialGradient(
                    colors: [
                      WholesalePromoBanner._cyan.withValues(alpha: 0.55),
                      WholesalePromoBanner._cyan.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: h * 0.02,
              child: Container(
                width: h * 0.95,
                height: h * 0.95,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.16),
                      Colors.white.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            // Spare parts (back, left) and membrane (front, right).
            Positioned(
              left: 0,
              bottom: h * 0.08,
              width: w * 0.58,
              height: h * 0.70,
              child: FloatingBannerProduct(
                child: Image.asset(
                  'assets/images/banners_cutout/spare_parts.png',
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
            Positioned(
              right: 0,
              bottom: h * 0.06,
              width: w * 0.62,
              height: h * 0.92,
              child: FloatingBannerProduct(
                child: Image.asset(
                  'assets/images/banners_cutout/membrane.png',
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.water_drop_rounded,
                    size: 55,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
