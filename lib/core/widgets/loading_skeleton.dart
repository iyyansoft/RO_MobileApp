import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class LoadingSkeleton extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;
  final ShapeBorder shape;

  const LoadingSkeleton({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = AppTheme.radiusS,
    this.shape = const RoundedRectangleBorder(),
  });

  const LoadingSkeleton.rectangular({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = AppTheme.radiusS,
  }) : shape = const RoundedRectangleBorder();

  const LoadingSkeleton.circular({
    super.key,
    required double size,
  })  : width = size,
        height = size,
        borderRadius = 9999.0,
        shape = const CircleBorder();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final baseColor = isDark ? const Color(0xFF1B2633) : const Color(0xFFE5EFF5);
    final highlightColor = isDark ? const Color(0xFF26374A) : const Color(0xFFF0F6FA);

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Container(
        width: width,
        height: height,
        decoration: shape == const CircleBorder()
            ? const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              )
            : BoxDecoration(
                borderRadius: BorderRadius.circular(borderRadius),
                color: Colors.white,
              ),
      ),
    );
  }
}
