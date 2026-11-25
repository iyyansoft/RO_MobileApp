import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/widgets/brand_logo.dart' show kBrandLogoAsset;
import '../../domain/category_price_view.dart';
import '../../domain/share_text_cleaner.dart';
import '../../domain/models/product_model.dart';
import '../../domain/models/product_share.dart';

// Card is laid out at 1080 x 1350 (4:5 portrait, WhatsApp-friendly) and
// rendered at 4/3 scale: a 1440 x 1800 px image.
const double _cardWidth = 1080;
const double _cardMinHeight = 1350;
const double _scale = 4 / 3;
const double _inset = 64;
const Color _ink = Color(0xFF0F2137);
const Color _muted = Color(0xFF5B6B7F);
const Color _accent = Color(0xFF0B5FD9);
const Color _accentSoft = Color(0xFFE6F0FD);
const Color _photoPanel = Colors.white;
const Color _line = Color(0xFFE2E8F0);
const String _logoAsset = kBrandLogoAsset;

/// The text printed on the share card, top to bottom: category, name, SKU and
/// one price (description, specifications and features go in the WhatsApp
/// message text, so the product photo stays large). The price is
/// [sharePrice]: MRP, or the Cabinet Price only when shared from the Cabinet
/// page; the dealer and purchase prices are never read.
List<String> shareCardText(
  ProductModel product, {
  ProductPriceView view = ProductPriceView.standard,
}) {
  final price = sharePrice(product, view: view);
  return [
    if (product.categoryName.trim().isNotEmpty)
      product.categoryName.trim().toUpperCase(),
    cleanShareItem(product.name),
    if (product.sku.trim().isNotEmpty) 'SKU: ${product.sku.trim()}',
    if (price != null) price.label,
    if (price != null) price.value,
  ];
}

/// Builds the WhatsApp product card (PNG) from the product's own photo bytes.
/// Without a usable photo (null, or bytes that are not an image) the photo
/// panel shows the app's water-drop placeholder: no other picture is used.
Future<Uint8List> renderProductShareCard(
  ProductModel product,
  Uint8List? photoBytes, {
  Uint8List? logoBytes,
  ProductPriceView view = ProductPriceView.standard,
}) async {
  ui.Image? photo;
  if (photoBytes != null && photoBytes.isNotEmpty) {
    try {
      photo = await _decode(photoBytes);
    } catch (_) {
      photo = null; // not an image: placeholder
    }
  }
  ui.Image? logo;
  try {
    final logoData = logoBytes ?? await _loadLogo();
    if (logoData != null) logo = await _decode(logoData);
  } catch (_) {
    logo = null; // the card is still complete without the logo
  }
  try {
    return await _paintShareCard(product, photo, logo, view);
  } finally {
    photo?.dispose();
    logo?.dispose();
  }
}

/// Same card from an image source (data URI, asset or backend path).
Future<Uint8List> renderProductShareImage(
  ProductModel product, {
  String? imageSource,
}) async {
  final source = imageSource ?? product.allImages.first;
  return renderProductShareCard(product, await _loadSource(source));
}

Future<Uint8List?> _loadLogo() async {
  try {
    final data = await rootBundle.load(_logoAsset);
    return data.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

Future<Uint8List> _loadSource(String source) async {
  if (source.startsWith('data:image/')) {
    return base64Decode(source.split(',').last);
  }
  if (source.startsWith('assets/') || source.startsWith('web_preview/')) {
    final data = await rootBundle.load(source);
    return data.buffer.asUint8List();
  }
  final url = Uri.parse(ApiClient.defaultBaseUrl)
      .resolve('/')
      .resolve(source)
      .toString();
  final data = await NetworkAssetBundle(Uri.parse(url)).load('');
  return data.buffer.asUint8List();
}

Future<ui.Image> _decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

TextPainter _text(
  String text, {
  required double size,
  FontWeight weight = FontWeight.w600,
  Color color = _ink,
  double letterSpacing = 0,
  int? maxLines,
  double maxWidth = _cardWidth - _inset * 2,
}) {
  return TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: size,
        fontWeight: weight,
        height: 1.18,
        letterSpacing: letterSpacing,
        fontFamily: 'Roboto',
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: maxLines,
    ellipsis: maxLines == null ? null : '…',
  )..layout(maxWidth: maxWidth);
}

Future<Uint8List> _paintShareCard(
  ProductModel product,
  ui.Image? photo,
  ui.Image? logo,
  ProductPriceView view,
) async {
  const contentWidth = _cardWidth - _inset * 2;
  const headerHeight = 148.0;
  const photoTop = headerHeight + 12;
  const photoHeight = 640.0;

  final category = product.categoryName.trim();
  final categoryText = category.isEmpty
      ? null
      : _text(
          category.toUpperCase(),
          size: 26,
          weight: FontWeight.w800,
          color: _accent,
          letterSpacing: 1.6,
          maxLines: 1,
          maxWidth: contentWidth - 48,
        );
  final name = _text(
    cleanShareItem(product.name),
    size: 54,
    weight: FontWeight.w800,
    maxLines: 3,
  );
  final sku = product.sku.trim().isEmpty
      ? null
      : _text('SKU: ${product.sku.trim()}', size: 32, color: _muted);
  final price = sharePrice(product, view: view);
  final hasMrp = price != null;
  final mrpLabel = _text(
    price?.label ?? '',
    size: 28,
    weight: FontWeight.w700,
    color: _muted,
  );
  final mrpValue = _text(
    price?.value ?? '',
    size: 84,
    weight: FontWeight.w900,
    color: _accent,
  );

  // Vertical layout.
  var y = photoTop + photoHeight + 40;
  final categoryTop = y;
  if (categoryText != null) y += categoryText.height + 20 + 28;
  final nameTop = y;
  y += name.height + 16;
  final skuTop = y;
  if (sku != null) y += sku.height + 36;
  final priceTop = y;
  if (hasMrp) y += 24 + mrpLabel.height + 4 + mrpValue.height + 24;
  final height = (y + 56).clamp(_cardMinHeight, 4000).toDouble();

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(_scale);
  final full = Rect.fromLTWH(0, 0, _cardWidth, height);
  canvas.drawRect(full, Paint()..color = Colors.white);

  // Header: brand logo and a thin accent rule.
  if (logo != null) {
    _drawContained(
      canvas,
      logo,
      const Rect.fromLTWH(_inset, 34, 300, headerHeight - 68),
      alignment: Alignment.centerLeft,
    );
  }
  canvas.drawRect(
    const Rect.fromLTWH(_inset, headerHeight - 2, contentWidth, 2),
    Paint()..color = _line,
  );

  // Product photo, fitted (never cropped) on a soft panel.
  final photoPanel = RRect.fromRectAndRadius(
    const Rect.fromLTWH(_inset, photoTop + 16, contentWidth, photoHeight - 16),
    const Radius.circular(36),
  );
  canvas.drawRRect(photoPanel, Paint()..color = _photoPanel);
  canvas.drawRRect(
    photoPanel,
    Paint()
      ..color = _line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2,
  );
  if (photo != null) {
    canvas.save();
    canvas.clipRRect(photoPanel);
    // Trim the white border around the product so it fills the panel.
    final content = await _contentBounds(photo);
    _drawContained(
      canvas,
      photo,
      photoPanel.outerRect.deflate(40),
      source: content,
    );
    canvas.restore();
  } else {
    _paintPlaceholder(canvas, photoPanel.outerRect);
  }

  // Category pill.
  if (categoryText != null) {
    final pill = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        _inset,
        categoryTop,
        categoryText.width + 48,
        categoryText.height + 20,
      ),
      const Radius.circular(40),
    );
    canvas.drawRRect(pill, Paint()..color = _accentSoft);
    categoryText.paint(canvas, Offset(_inset + 24, categoryTop + 10));
  }

  name.paint(canvas, Offset(_inset, nameTop));
  sku?.paint(canvas, Offset(_inset, skuTop));

  // Price block (the only price on the card: MRP or Cabinet Price).
  if (hasMrp) {
    final box = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        _inset,
        priceTop,
        contentWidth,
        24 + mrpLabel.height + 4 + mrpValue.height + 24,
      ),
      const Radius.circular(28),
    );
    canvas.drawRRect(box, Paint()..color = _accentSoft);
    mrpLabel.paint(canvas, Offset(_inset + 32, priceTop + 24));
    mrpValue.paint(
      canvas,
      Offset(_inset + 32, priceTop + 24 + mrpLabel.height + 4),
    );
  }

  // Footer accent.
  canvas.drawRect(
    Rect.fromLTWH(0, height - 14, _cardWidth, 14),
    Paint()..color = _accent,
  );

  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (_cardWidth * _scale).round(),
    (height * _scale).round(),
  );
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Could not encode the product card.');
    return data.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

/// The app's water-drop placeholder, centred in the photo panel, used when
/// the product's own image cannot be loaded (no other picture is used).
void _paintPlaceholder(Canvas canvas, Rect panel) {
  canvas.drawRRect(
    RRect.fromRectAndRadius(panel.deflate(2), const Radius.circular(34)),
    Paint()..color = const Color(0xFFF1F7FD),
  );
  const icon = Icons.water_drop_rounded;
  final painter = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: 220,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: const Color(0xFF93C5FD),
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(
    canvas,
    panel.center - Offset(painter.width / 2, painter.height / 2),
  );
}

/// The part of [image] that is not near-white background (whole image when
/// it has no such border).
Future<Rect> _contentBounds(ui.Image image) async {
  final whole = Rect.fromLTWH(
    0,
    0,
    image.width.toDouble(),
    image.height.toDouble(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) return whole;
  final w = image.width, h = image.height;
  var left = w, top = h, right = -1, bottom = -1;
  for (var y = 0; y < h; y += 2) {
    final row = y * w * 4;
    for (var x = 0; x < w; x += 2) {
      final i = row + x * 4;
      final a = data.getUint8(i + 3);
      if (a < 16) continue;
      final r = data.getUint8(i),
          g = data.getUint8(i + 1),
          b = data.getUint8(i + 2);
      if (r > 240 && g > 240 && b > 240) continue;
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
    }
  }
  if (right < left || bottom < top) return whole;
  const pad = 8.0;
  return Rect.fromLTRB(
    (left - pad).clamp(0, w).toDouble(),
    (top - pad).clamp(0, h).toDouble(),
    (right + pad + 2).clamp(0, w).toDouble(),
    (bottom + pad + 2).clamp(0, h).toDouble(),
  );
}

void _drawContained(
  Canvas canvas,
  ui.Image image,
  Rect destination, {
  Alignment alignment = Alignment.center,
  Rect? source,
}) {
  final area =
      source ??
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
  final fit = applyBoxFit(BoxFit.contain, area.size, destination.size);
  final sourceRect = Alignment.center.inscribe(fit.source, area);
  final outputRect = alignment.inscribe(fit.destination, destination);
  canvas.drawImageRect(
    image,
    sourceRect,
    outputRect,
    Paint()..filterQuality = FilterQuality.high,
  );
}
