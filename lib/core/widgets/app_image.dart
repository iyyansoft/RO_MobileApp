import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../network/api_client.dart';

class AppImage extends StatelessWidget {
  final String source;
  final BoxFit? fit;
  final double? width, height;
  final ImageErrorWidgetBuilder? errorBuilder;
  const AppImage(
    this.source, {
    super.key,
    this.fit,
    this.width,
    this.height,
    this.errorBuilder,
  });

  @override
  Widget build(BuildContext context) {
    Widget fallback(BuildContext context, Object error, StackTrace? stack) =>
        errorBuilder?.call(context, error, stack) ??
        SizedBox(
          width: width,
          height: height,
          child: const Icon(Icons.image_not_supported_outlined),
        );
    if (source.trim().isEmpty) {
      return fallback(
        context,
        const FormatException('Image source is unavailable'),
        null,
      );
    }
    if (source.startsWith('catalog-sprite://')) {
      final tile = int.tryParse(source.substring('catalog-sprite://'.length));
      if (tile == null || tile < 0 || tile >= 20) {
        return fallback(
          context,
          const FormatException('Invalid catalog image'),
          null,
        );
      }
      return _CatalogSpriteImage(
        tile: tile,
        width: width,
        height: height,
        fit: fit ?? BoxFit.contain,
        errorBuilder: errorBuilder,
      );
    }
    if (source.startsWith('data:image/')) {
      try {
        return Image.memory(
          base64Decode(source.split(',').last),
          fit: fit,
          width: width,
          height: height,
          errorBuilder: fallback,
        );
      } catch (error) {
        return fallback(context, error, null);
      }
    }
    if (source.startsWith('assets/') || source.startsWith('web_preview/')) {
      return Image.asset(
        source,
        fit: fit,
        width: width,
        height: height,
        errorBuilder: fallback,
      );
    }
    final base = Uri.parse(ApiClient.defaultBaseUrl).resolve('/');
    final url = base.resolve(source).toString();
    return Image.network(
      url,
      fit: fit,
      width: width,
      height: height,
      errorBuilder: fallback,
    );
  }
}

class _CatalogSpriteImage extends StatefulWidget {
  final int tile;
  final BoxFit fit;
  final double? width;
  final double? height;
  final ImageErrorWidgetBuilder? errorBuilder;

  const _CatalogSpriteImage({
    required this.tile,
    required this.fit,
    required this.width,
    required this.height,
    required this.errorBuilder,
  });

  @override
  State<_CatalogSpriteImage> createState() => _CatalogSpriteImageState();
}

class _CatalogSpriteImageState extends State<_CatalogSpriteImage> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageInfo? _imageInfo;
  Object? _error;
  StackTrace? _stackTrace;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final stream = const AssetImage(
      'assets/images/ro_product_catalog_sprite.png',
    ).resolve(createLocalImageConfiguration(context));
    if (_stream == stream) return;
    _removeListener();
    _stream = stream;
    _listener = ImageStreamListener(
      (info, synchronousCall) {
        final previous = _imageInfo;
        setState(() {
          _imageInfo = info;
          _error = null;
          _stackTrace = null;
        });
        previous?.dispose();
      },
      onError: (error, stackTrace) {
        setState(() {
          _error = error;
          _stackTrace = stackTrace;
        });
      },
    );
    stream.addListener(_listener!);
  }

  void _removeListener() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _listener = null;
    _stream = null;
  }

  @override
  void dispose() {
    _removeListener();
    _imageInfo?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error case final error?) {
      return widget.errorBuilder?.call(context, error, _stackTrace) ??
          SizedBox(
            width: widget.width,
            height: widget.height,
            child: const Icon(Icons.image_not_supported_outlined),
          );
    }
    final image = _imageInfo?.image;
    if (image == null) {
      return SizedBox(width: widget.width, height: widget.height);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            widget.width ??
            (constraints.maxWidth.isFinite ? constraints.maxWidth : 120.0);
        final height =
            widget.height ??
            (constraints.maxHeight.isFinite ? constraints.maxHeight : 120.0);
        final size = Size(width, height);
        return CustomPaint(
          size: size,
          painter: _CatalogSpritePainter(
            image: image,
            tile: widget.tile,
            fit: widget.fit,
          ),
          child: SizedBox(width: width, height: height),
        );
      },
    );
  }
}

class _CatalogSpritePainter extends CustomPainter {
  final ui.Image image;
  final int tile;
  final BoxFit fit;

  const _CatalogSpritePainter({
    required this.image,
    required this.tile,
    required this.fit,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const columns = 5;
    const rows = 4;
    final cellWidth = image.width / columns;
    final cellHeight = image.height / rows;
    final col = tile % columns;
    final row = tile ~/ columns;
    final insetX = cellWidth * 0.035;
    final insetY = cellHeight * 0.035;
    final source = Rect.fromLTWH(
      col * cellWidth + insetX,
      row * cellHeight + insetY,
      cellWidth - insetX * 2,
      cellHeight - insetY * 2,
    );
    final fitted = applyBoxFit(fit, source.size, size);
    final sourceRect = Alignment.center.inscribe(fitted.source, source);
    final destinationRect = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
    canvas.drawImageRect(
      image,
      sourceRect,
      destinationRect,
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  @override
  bool shouldRepaint(covariant _CatalogSpritePainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.tile != tile ||
      oldDelegate.fit != fit;
}
