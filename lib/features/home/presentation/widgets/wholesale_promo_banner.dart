import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Full-width promo banner on the Home page (below Best Sellers): the
/// finished artwork `assets/images/big_banner.png` (heading, chips, button
/// and products are part of the image).
///
/// Width 100%. The height follows the image's own 3:1 shape, so the whole
/// banner is visible on desktop and tablet; on narrow phones it keeps a
/// minimum height and the image covers the box (like CSS object-fit: cover),
/// anchored left so the heading and button stay in view. Tapping anywhere
/// on it opens the catalogue ([onExplore]).
class WholesalePromoBanner extends StatelessWidget {
  const WholesalePromoBanner({
    super.key,
    required this.isDesktop,
    required this.onExplore,
  });

  static const image = 'assets/images/big_banner.png';

  /// big_banner.png is 2172 x 724.
  static const aspectRatio = 2172 / 724;
  static const minHeight = 150.0;

  final bool isDesktop;
  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final wide = width >= 720;
        final height = math.max(width / aspectRatio, minHeight);
        final radius = BorderRadius.circular(wide ? 28 : 22);

        return Semantics(
          button: true,
          label:
              'High TDS Membranes & Commercial Spares. '
              'Explore RO Spares Collection',
          child: Container(
            key: const ValueKey('wholesale-promo-banner'),
            width: double.infinity,
            height: height,
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0369A1).withValues(alpha: 0.30),
                  blurRadius: 30,
                  spreadRadius: -8,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: Material(
                color: const Color(0xFF0B3A6E), // shown while the image loads
                child: InkWell(
                  onTap: onExplore,
                  child: Ink(
                    width: double.infinity,
                    height: height,
                    decoration: const BoxDecoration(
                      image: DecorationImage(
                        image: AssetImage(image),
                        fit: BoxFit.cover,
                        alignment: Alignment.centerLeft,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
