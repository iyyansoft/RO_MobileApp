import '../../../../core/network/api_client.dart';
import '../../../../core/utils/rupee_format.dart';
import '../category_price_view.dart';
import '../share_text_cleaner.dart';
import 'product_model.dart';

/// MRP for shared content, e.g. "₹12,000". Shared content never uses
/// [ProductModel.dealerPrice] or [ProductModel.purchasePrice].
String mrpSharePrice(ProductModel product) => rupee(product.mrp);

/// The one price a share shows (text, card image and share page).
class SharePrice {
  const SharePrice(this.label, this.amount);

  /// "Cabinet Price" or "MRP".
  final String label;
  final double amount;

  String get value => rupee(amount);
}

/// Shared from the Cabinet page ([view] shows the Cabinet Price only): the
/// Cabinet Price, never MRP or Dealer Price. Everywhere else: MRP only. Never
/// the dealer or purchase price. Null when there is no price to show.
SharePrice? sharePrice(
  ProductModel product, {
  ProductPriceView view = ProductPriceView.standard,
}) {
  if (view.cabinetOnly(product)) {
    return SharePrice('Cabinet Price', product.cabinetPrice!);
  }
  if (product.mrp > 0) return SharePrice('MRP', product.mrp);
  return null;
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
/// The price is [sharePrice]: MRP, or the Cabinet Price only when shared
/// from the Cabinet page; never the dealer or purchase price.
/// No product link or other URL, and no supplier/distributor references
/// (see [cleanShareText]).
String productShareText(
  ProductModel product, {
  ProductPriceView view = ProductPriceView.standard,
}) {
  final price = sharePrice(product, view: view);
  final description = cleanShareText(product.description);
  final specs = shareSpecRows(product);
  final features = shareFeatures(product);
  final details = <String>[
    'Product Name: ${cleanShareItem(product.name)}',
    if (product.sku.trim().isNotEmpty) 'Product Code (SKU): ${product.sku}',
    if (product.brand.trim().isNotEmpty) 'Brand: ${product.brand}',
    if (product.categoryName.trim().isNotEmpty)
      'Category: ${product.categoryName}',
    if (price != null) '${price.label}: ${price.value}',
    'Availability: ${product.stockStatus.label}',
    product.moqSet ? 'MOQ: ${product.moq}' : 'MOQ not set',
  ];

  if (description.isNotEmpty) {
    details.add('Description: $description');
  }
  if (specs.isNotEmpty) {
    details.add('Specifications:');
    for (final (label, value) in specs) {
      details.add(label.isEmpty ? value : '$label: $value');
    }
  }
  if (features.isNotEmpty) {
    details.add('Features:');
    details.addAll(
      features.map((feature) => '${String.fromCharCode(0x2022)} $feature'),
    );
  }
  if (product.rating > 0) {
    details.add(
      'Rating: ${product.rating}'
      '${product.reviewCount > 0 ? ' (${product.reviewCount} reviews)' : ''}',
    );
  }
  return details.join('\n');
}

/// Opens WhatsApp (the app, or WhatsApp Web on desktop) with the product
/// details as the message ([whatsAppShareText]: no product link).
Uri whatsAppShareUri(
  ProductModel product, {
  ProductPriceView view = ProductPriceView.standard,
}) => Uri.https('wa.me', '/', {'text': whatsAppShareText(product, view: view)});

/// Optional enquiry line printed on the product card and added to the
/// WhatsApp message (hidden when empty), set at build time, e.g.
/// `--dart-define=SHARE_CONTACT="Enquiry: +91 98xxxxxxx · sales@neeroplus.in"`.
const kShareContact = String.fromEnvironment('SHARE_CONTACT');

/// Specification rows entered in the Admin Dashboard, as (label, value),
/// cleaned for sharing ([cleanShareItem]: no supplier/distributor notes).
/// Free text saved by the admin form (key "details") has an empty label.
/// Blank rows are left out.
List<(String, String)> shareSpecRows(ProductModel product) => [
  for (final e in product.specifications.entries)
    if (cleanShareItem(e.value).isNotEmpty)
      (
        e.key.trim().toLowerCase() == 'details'
            ? ''
            : cleanShareItem(e.key.trim()),
        e.key.trim().toLowerCase() == 'details'
            ? cleanShareText(e.value)
            : cleanShareItem(e.value),
      ),
];

/// Key features entered in the Admin Dashboard, cleaned for sharing
/// ([cleanShareItem]); blank lines left out.
List<String> shareFeatures(ProductModel product) => [
  for (final f in product.features)
    if (cleanShareItem(f).isNotEmpty) cleanShareItem(f),
];

/// WhatsApp message sent with the product image: every detail entered in
/// the Admin Dashboard as readable text (the image itself shows only the
/// photo, category, name, SKU and MRP). Sections without data are left out;
/// the description, specification values and features keep their own line
/// breaks. One price ([sharePrice]: MRP, or the Cabinet Price from the Cabinet
/// page), never the dealer or purchase price. No product link or other URL:
/// the message ends with the contact line.
String whatsAppShareText(
  ProductModel product, {
  ProductPriceView view = ProductPriceView.standard,
}) {
  final price = sharePrice(product, view: view);
  // No supplier/distributor references (see [cleanShareText]).
  final description = cleanShareText(product.description);
  final specs = shareSpecRows(product);
  final features = shareFeatures(product);
  final blocks = <String>[
    'Product Name: ${cleanShareItem(product.name)}',
    if (product.sku.trim().isNotEmpty) 'SKU: ${product.sku.trim()}',
    if (product.categoryName.trim().isNotEmpty)
      'Category: ${product.categoryName.trim()}',
    if (product.brand.trim().isNotEmpty) 'Brand: ${product.brand.trim()}',
    if (price != null) '${price.label}: ${price.value}',
    if (description.isNotEmpty) 'DESCRIPTION:\n$description',
    if (specs.isNotEmpty)
      'SPECIFICATIONS:\n${specs.map((s) => s.$1.isEmpty ? s.$2 : '${s.$1}: ${s.$2}').join('\n')}',
    if (features.isNotEmpty)
      'KEY FEATURES:\n${features.map((f) => '- $f').join('\n')}',
    [
      'Contact us for orders and enquiries.',
      if (kShareContact.trim().isNotEmpty) kShareContact.trim(),
    ].join('\n'),
  ];
  return blocks.join('\n\n');
}
