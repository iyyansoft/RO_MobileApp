import 'package:flutter/material.dart';

/// A category picture: [savedUrl] (the image saved in the Admin Panel) first;
/// if there is none or it cannot be loaded, [builtInUrl] (the app's own
/// picture for the category); then [fallback].
Widget categoryPicture({
  String? savedUrl,
  String? builtInUrl,
  required Widget fallback,
}) {
  final builtIn = builtInUrl != null
      ? CategoryImage(url: builtInUrl, fallback: fallback)
      : fallback;
  if (savedUrl != null && savedUrl != builtInUrl) {
    return CategoryImage(url: savedUrl, fallback: builtIn);
  }
  return builtIn;
}

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
    // Same file bundled at assets/images/<path under /images/>, keeping any
    // sub-folder (e.g. products_image/...).
    final segments = Uri.parse(url).pathSegments;
    final at = segments.indexOf('images');
    final assetPath =
        'assets/images/${(at >= 0 ? segments.sublist(at + 1) : [segments.last]).join('/')}';
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
