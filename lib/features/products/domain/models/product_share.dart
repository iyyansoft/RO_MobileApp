import '../../../../core/network/api_client.dart';
import '../../../../core/utils/rupee_format.dart';
import 'product_model.dart';

/// MRP for shared content, e.g. "₹12,000". Shared content never uses
/// [ProductModel.dealerPrice] or [ProductModel.purchasePrice].
String mrpSharePrice(ProductModel product) => rupee(product.mrp);

/// Deployed backend that serves the public share pages.
const kPublicShareOrigin = 'https://ro-mobileapp.onrender.com';

/// Optional build-time override, e.g.
/// `--dart-define=PUBLIC_SHARE_BASE_URL=https://share.example.com`.
const _configuredShareBase = String.fromEnvironment('PUBLIC_SHARE_BASE_URL');

bool _isPrivateHost(String host) {
  final h = host.toLowerCase();
  return h == 'localhost' ||
      h.endsWith('.local') ||
      h == '127.0.0.1' ||
      h == '0.0.0.0' ||
      h == '10.0.2.2' ||
      h.startsWith('10.') ||
      h.startsWith('192.168.') ||
      RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(h);
}

/// Public product page used for shared links. It is served by the backend
/// (`/share/products/<id>`) with Open Graph tags (image, title, MRP only), so
/// WhatsApp shows a rich preview and the link opens this product.
///
/// WhatsApp builds previews on its own servers, so a localhost or LAN link
/// can never show an image; those fall back to the deployed backend.
Uri productShareUrl(
  ProductModel product, {
  String? apiBaseUrl,
  String? publicBaseUrl,
}) {
  final configured = publicBaseUrl ?? _configuredShareBase;
  Uri base;
  if (configured.trim().isNotEmpty) {
    base = Uri.parse(configured.trim());
  } else {
    final api = Uri.parse(apiBaseUrl ?? ApiClient.defaultBaseUrl);
    base = _isPrivateHost(api.host) ? Uri.parse(kPublicShareOrigin) : api;
  }
  return base.resolve('/share/products/${Uri.encodeComponent(product.id)}');
}

/// The product's own image as a file (same picture as the app and the share
/// page's og:image). Fetched from the backend the app already uses, so it
/// also works while developing locally.
Uri productImageFileUrl(ProductModel product, {String? apiBaseUrl}) {
  final api = Uri.parse(apiBaseUrl ?? ApiClient.defaultBaseUrl);
  return api.resolve(
    '/share/products/${Uri.encodeComponent(product.id)}/image',
  );
}

/// Product information shared alongside the generated product card.
///
/// Prices in this payload deliberately come only from [ProductModel.mrp].
String productShareText(ProductModel product, {Uri? link}) {
  final details = <String>[
    'Product Name: ${product.name}',
    if (product.sku.trim().isNotEmpty) 'Product Code (SKU): ${product.sku}',
    if (product.brand.trim().isNotEmpty) 'Brand: ${product.brand}',
    if (product.categoryName.trim().isNotEmpty)
      'Category: ${product.categoryName}',
    if (product.mrp > 0) 'MRP: ${mrpSharePrice(product)}',
    'Availability: ${product.stockStatus.label}',
    product.moqSet ? 'MOQ: ${product.moq}' : 'MOQ not set',
  ];

  if (product.description.trim().isNotEmpty) {
    details.add('Description: ${product.description.trim()}');
  }
  if (product.specifications.isNotEmpty) {
    details.add('Specifications:');
    for (final entry in product.specifications.entries) {
      details.add('${entry.key}: ${entry.value}');
    }
  }
  if (product.features.isNotEmpty) {
    details.add('Features:');
    details.addAll(
      product.features.map(
        (feature) => '${String.fromCharCode(0x2022)} $feature',
      ),
    );
  }
  if (product.rating > 0) {
    details.add(
      'Rating: ${product.rating}'
      '${product.reviewCount > 0 ? ' (${product.reviewCount} reviews)' : ''}',
    );
  }
  if (link != null) {
    details.add('View product: $link');
  }

  return details.join('\n');
}

/// WhatsApp share link (opens the WhatsApp app, or WhatsApp Web on desktop)
/// with the product details and its page link. WhatsApp builds the image
/// preview from that page's Open Graph tags, which carry MRP only.
Uri whatsAppShareUri(ProductModel product, {String? apiBaseUrl}) => Uri.https(
  'wa.me',
  '/',
  {'text': whatsAppShareText(product, apiBaseUrl: apiBaseUrl)},
);

/// Message sent to WhatsApp: details with MRP only, then the product page
/// link (last, so WhatsApp builds its photo preview from it).
String whatsAppShareText(ProductModel product, {String? apiBaseUrl}) {
  final link = productShareUrl(product, apiBaseUrl: apiBaseUrl);
  return [
    '*${product.name}*',
    if (product.mrp > 0) 'MRP: ${mrpSharePrice(product)}',
    if (product.sku.trim().isNotEmpty) 'SKU: ${product.sku}',
    if (product.brand.trim().isNotEmpty) 'Brand: ${product.brand}',
    if (product.categoryName.trim().isNotEmpty)
      'Category: ${product.categoryName}',
    if (product.description.trim().isNotEmpty) product.description.trim(),
    '',
    link.toString(),
  ].join('\n');
}
