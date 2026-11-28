import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_model.dart';

/// The share page (server.js productShareImagePath) reads the list of old
/// shared demo image names from web_preview/share-images/catalog-image-map.json.
/// The app (ProductModel.displayImageUrl) and the share page must agree: a
/// demo name or an empty image is "no picture yet" (placeholder) – never a
/// sprite tile or another product's photo – and a real image is used as stored.
void main() {
  final map =
      jsonDecode(
            File(
              'web_preview/share-images/catalog-image-map.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final placeholders = (map['placeholders'] as List).cast<String>();

  ProductModel product(String sku, String key, String title, String img) =>
      ProductModel.fromJson({
        'id': sku,
        'sku': sku,
        'name': sku,
        'category': key,
        'category_name': title,
        'img': img,
        'price': 1,
        'mrp': 2,
      });

  test('the share page and the app use the same list of old demo names', () {
    expect(placeholders.toSet(), ProductModel.legacyPlaceholderImages);
  });

  test('an old demo name or an empty image shows no picture (placeholder), for every SKU and category', () {
    const categories = [
      ('systems', 'RO Systems'),
      ('membranes', 'Membranes'),
      ('filters', 'Filters & Cartridges'),
      ('pumps', 'Booster Pumps'),
      ('spares', 'Spare Parts & Valves'),
    ];
    for (final sku in ['RO-FLT-CTO', 'RO-SYS-10L', 'RO-SYS-25', 'PUMP-100GPD-24V', 'NEW-SKU-1']) {
      for (final (key, title) in categories) {
        for (final img in [...placeholders, '', '  ', '/purifier.jpg', 'PURIFIER.JPG']) {
          expect(
            product(sku, key, title, img).displayImageUrl,
            '',
            reason: '$sku $key "$img"',
          );
        }
      }
    }
  });

  test('uploaded photos are used as they are', () {
    final p = product('RO-FLT-CTO', 'filters', 'Filters', '/uploads/prod_1_2.jpg');
    expect(p.displayImageUrl, '/uploads/prod_1_2.jpg');
    expect(placeholders.contains('prod_1_2.jpg'), isFalse);
    expect(
      product('X', 'systems', 'RO Systems', 'tank.jpg').displayImageUrl,
      'tank.jpg',
    );
  });

  test('a full image URL saved in Admin is always shown as-is, even with a placeholder file name', () {
    const supabase =
        'https://abc.supabase.co/storage/v1/object/public/ro-product-images';
    for (final url in [
      '$supabase/booster-pumps/Max%20flow%20pump%201%20year%20warranty%20100%20gpd.jpg',
      '$supabase/membrane/membrane.jpg',
      '$supabase/pdf-catalog/CAB-36.jpg',
      'https://ro-mobileapp.onrender.com/purifier.jpg',
    ]) {
      expect(product('MUK-02', 'pumps', 'Booster Pumps', url).displayImageUrl, url);
      expect(product('RO-PMP-100', 'pumps', 'Booster Pumps', url).allImages, [url]);
    }
  });
}
