import 'package:flutter/material.dart';

/// Shows a category image from its backend URL without cropping.
///
/// If the URL fails (offline, server asleep, not yet deployed), falls back to
/// the same file bundled at `assets/images/<filename>`, then to [fallback].
class CategoryImage extends StatelessWidget {
  const CategoryImage({super.key, required this.url, required this.fallback});

  final String url;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final assetPath = 'assets/images/${Uri.parse(url).pathSegments.last}';
    return Image.network(
      url,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => Image.asset(
        assetPath,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}
