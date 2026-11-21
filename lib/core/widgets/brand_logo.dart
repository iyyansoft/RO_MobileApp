import 'package:flutter/material.dart';

/// The NeeroPlus logo used everywhere in the app (header, footer, splash,
/// login, admin, Shop app, share cards). Change it here only.
const kBrandLogoAsset = 'assets/images/neero_logo1.png';

/// Shared brand mark (always shown whole: BoxFit.contain, never stretched). The asset has a transparent background; on dark
/// surfaces [onDark] adds a small white surface to preserve contrast.
class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    this.width = 220,
    this.height = 79,
    this.onDark = false,
    this.alignment = Alignment.center,
    this.fit = BoxFit.contain,
  });

  final double width;
  final double height;
  final bool onDark;
  final AlignmentGeometry alignment;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: DecoratedBox(
      decoration: onDark
          ? BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            )
          : const BoxDecoration(),
      child: Padding(
        padding: onDark
            ? width < 100
                  ? const EdgeInsets.symmetric(horizontal: 2, vertical: 1)
                  : const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
            : EdgeInsets.zero,
        child: Image.asset(
          kBrandLogoAsset,
          fit: fit,
          alignment: alignment,
          filterQuality: FilterQuality.high,
          semanticLabel: 'NeeroPlus logo',
        ),
      ),
    ),
  );
}
