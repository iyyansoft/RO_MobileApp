import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/network/api_client.dart';
import '../../domain/models/product_model.dart';
import '../../domain/models/product_share.dart';

const double _cardWidth = 1080;
const double _cardPadding = 64;
const Color _ink = Color(0xFF14243A);
const Color _muted = Color(0xFF64748B);
const Color _accent = Color(0xFF2457C5);
const Color _paper = Color(0xFFF4F7FC);

/// Renders the original product photo with a clear product information card.
/// Only MRP is included as a price; dealer and purchase prices are never read.
Future<Uint8List> renderProductShareImage(
  ProductModel product, {
  String? imageSource,
}) async {
  final source = imageSource ?? product.allImages.first;
  final photo = await _loadImage(source);
  try {
    return await _paintShareCard(product, photo);
  } finally {
    photo.dispose();
  }
}

Future<ui.Image> _loadImage(String source) async {
  late Uint8List bytes;
  if (source.startsWith('data:image/')) {
    bytes = base64Decode(source.split(',').last);
  } else if (source.startsWith('assets/') ||
      source.startsWith('web_preview/')) {
    final data = await rootBundle.load(source);
    bytes = data.buffer.asUint8List();
  } else {
    final url = Uri.parse(ApiClient.defaultBaseUrl)
        .resolve('/')
        .resolve(source)
        .toString();
    final data = await NetworkAssetBundle(Uri.parse(url)).load('');
    bytes = data.buffer.asUint8List();
  }
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    return frame.image;
  } finally {
    codec.dispose();
  }
}

Future<Uint8List> _paintShareCard(ProductModel product, ui.Image photo) async {
  const horizontalInset = _cardPadding;
  const contentWidth = _cardWidth - horizontalInset * 2;
  const photoHeight = 500.0;
  const photoTop = 0.0;
  const bodyTop = photoTop + photoHeight + 42;

  final blocks = <_CardText>[
    _CardText(
      product.name,
      fontSize: 48,
      weight: FontWeight.w800,
      gapAfter: 24,
    ),
    if (product.brand.trim().isNotEmpty)
      _CardText('Brand: ${product.brand.trim()}', fontSize: 27, color: _muted),
    if (product.sku.trim().isNotEmpty)
      _CardText(
        'Product Code (SKU): ${product.sku.trim()}',
        fontSize: 27,
        color: _muted,
      ),
    if (product.categoryName.trim().isNotEmpty)
      _CardText(
        'Category: ${product.categoryName.trim()}',
        fontSize: 27,
        color: _muted,
        gapAfter: 22,
      ),
    const _CardText('MRP', fontSize: 24, color: _muted, gapAfter: 2),
    _CardText(
      '${String.fromCharCode(0x20B9)}${mrpSharePrice(product)}',
      fontSize: 52,
      weight: FontWeight.w800,
      color: _accent,
      gapAfter: 26,
    ),
    _CardText(
      'Availability: ${product.stockStatus.label}',
      fontSize: 27,
      weight: FontWeight.w700,
    ),
    _CardText('MOQ: ${product.moq}', fontSize: 27, color: _muted, gapAfter: 28),
    if (product.description.trim().isNotEmpty)
      _CardText(
        'Description\n${product.description.trim()}',
        fontSize: 26,
        gapAfter: 24,
      ),
    if (product.specifications.isNotEmpty)
      _CardText(
        'Specifications\n${product.specifications.entries.map((e) => '${e.key}: ${e.value}').join('\n')}',
        fontSize: 25,
        gapAfter: 24,
      ),
    if (product.features.isNotEmpty)
      _CardText(
        'Features\n${product.features.map((item) => '${String.fromCharCode(0x2022)} $item').join('\n')}',
        fontSize: 25,
      ),
    if (product.rating > 0)
      _CardText(
        'Rating: ${product.rating}${product.reviewCount > 0 ? ' (${product.reviewCount} reviews)' : ''}',
        fontSize: 24,
        color: _muted,
        gapBefore: 24,
      ),
  ];

  final layouts = blocks.map((block) => block.layout(contentWidth)).toList();
  final bodyHeight = layouts.fold<double>(
    0,
    (height, layout) =>
        height + layout.height + layout.block.gapBefore + layout.block.gapAfter,
  );
  final cardHeight = bodyTop + bodyHeight + 64;
  final sizedRecorder = ui.PictureRecorder();
  final sizedCanvas = Canvas(
    sizedRecorder,
    Rect.fromLTWH(0, 0, _cardWidth, cardHeight),
  );

  sizedCanvas.drawRect(
    Rect.fromLTWH(0, 0, _cardWidth, cardHeight),
    Paint()..color = Colors.white,
  );
  sizedCanvas.drawRect(
    const Rect.fromLTWH(0, 0, _cardWidth, photoHeight),
    Paint()..color = _paper,
  );
  _drawContainedImage(
    sizedCanvas,
    photo,
    const Rect.fromLTWH(36, 28, _cardWidth - 72, photoHeight - 56),
  );

  var y = bodyTop;
  for (final layout in layouts) {
    y += layout.block.gapBefore;
    layout.painter.paint(sizedCanvas, Offset(horizontalInset, y));
    y += layout.height + layout.block.gapAfter;
  }

  sizedCanvas.drawRect(
    Rect.fromLTWH(horizontalInset, cardHeight - 12, contentWidth, 8),
    Paint()..color = _accent,
  );
  final picture = sizedRecorder.endRecording();
  final image = await picture.toImage(_cardWidth.toInt(), cardHeight.ceil());
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Could not encode product share card');
    return data.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void _drawContainedImage(Canvas canvas, ui.Image image, Rect destination) {
  final sourceSize = Size(image.width.toDouble(), image.height.toDouble());
  final fit = applyBoxFit(BoxFit.contain, sourceSize, destination.size);
  final sourceRect = Alignment.center.inscribe(
    fit.source,
    Offset.zero & sourceSize,
  );
  final outputRect = Alignment.center.inscribe(fit.destination, destination);
  canvas.drawImageRect(
    image,
    sourceRect,
    outputRect,
    Paint()..filterQuality = FilterQuality.high,
  );
}

class _CardText {
  final String text;
  final double fontSize;
  final FontWeight weight;
  final Color color;
  final double gapBefore;
  final double gapAfter;

  const _CardText(
    this.text, {
    required this.fontSize,
    this.weight = FontWeight.w500,
    this.color = _ink,
    this.gapBefore = 0,
    this.gapAfter = 12,
  });

  _LaidOutCardText layout(double width) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: weight,
          height: 1.28,
          fontFamily: 'Roboto',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width);
    return _LaidOutCardText(this, painter, painter.height);
  }
}

class _LaidOutCardText {
  final _CardText block;
  final TextPainter painter;
  final double height;

  const _LaidOutCardText(this.block, this.painter, this.height);
}
