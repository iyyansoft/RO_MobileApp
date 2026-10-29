import 'package:flutter/material.dart';

/// Shared RO brand mark. The asset has a transparent background; on dark
/// surfaces [onDark] adds a small white surface to preserve contrast.
class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    this.width = 220,
    this.height = 79,
    this.onDark = false,
    this.alignment = Alignment.center,
  });

  final double width;
  final double height;
  final bool onDark;
  final AlignmentGeometry alignment;

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
        child: ClipRect(
          child: Image.asset(
            'assets/images/RO_LOGO.png',
            fit: BoxFit.cover,
            alignment: alignment,
            filterQuality: FilterQuality.high,
            semanticLabel: 'RO logo',
          ),
        ),
      ),
    ),
  );
}
