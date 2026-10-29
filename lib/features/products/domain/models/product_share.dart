import 'product_model.dart';

String mrpSharePrice(ProductModel product) => product.mrp.toStringAsFixed(
  product.mrp == product.mrp.roundToDouble() ? 0 : 2,
);

/// Product information shared alongside the generated product card.
///
/// Prices in this payload deliberately come only from [ProductModel.mrp].
String productShareText(ProductModel product) {
  final details = <String>[
    'Product Name: ${product.name}',
    if (product.sku.trim().isNotEmpty) 'Product Code (SKU): ${product.sku}',
    if (product.brand.trim().isNotEmpty) 'Brand: ${product.brand}',
    if (product.categoryName.trim().isNotEmpty)
      'Category: ${product.categoryName}',
    'MRP: ${String.fromCharCode(0x20B9)}${mrpSharePrice(product)}',
    'Availability: ${product.stockStatus.label}',
    'MOQ: ${product.moq}',
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

  return details.join('\n');
}
