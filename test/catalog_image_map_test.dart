import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_model.dart';

/// The share page (server.js) picks a product's preview picture from
/// web_preview/share-images/catalog-image-map.json. It must pick exactly the
/// picture the app shows (ProductModel.displayImageUrl), or WhatsApp would
/// show a different product's image.
void main() {
  final map =
      jsonDecode(
            File(
              'web_preview/share-images/catalog-image-map.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final placeholders = (map['placeholders'] as List).cast<String>();
  final bySku = (map['bySku'] as Map).cast<String, int>();
  final rules = (map['byCategoryText'] as List).cast<Map>();

  int? serverTile(String sku, String categoryKey, String categoryTitle) {
    final direct = bySku[sku.toUpperCase()];
    if (direct != null) return direct;
    final text = '$categoryKey $categoryTitle'.toLowerCase();
    for (final rule in rules) {
      if ((rule['contains'] as List).any((w) => text.contains(w as String))) {
        return rule['tile'] as int;
      }
    }
    return map['defaultTile'] as int;
  }

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

  test('every mapped SKU gets the same picture in the app and on share pages', () {
    for (final entry in bySku.entries) {
      for (final img in placeholders) {
        final app = product(entry.key, 'x', 'x', img).displayImageUrl;
        expect(app, 'catalog-sprite://${entry.value}', reason: entry.key);
        expect(
          File('web_preview/share-images/catalog-${entry.value}.jpg').existsSync(),
          isTrue,
        );
      }
    }
  });

  test('unmapped SKUs follow the same category rule in the app and on share pages', () {
    const categories = [
      ('systems', 'RO Systems'),
      ('membranes', 'Membranes'),
      ('filters', 'Filters & Cartridges'),
      ('pumps', 'Booster Pumps'),
      ('pipes', 'Pipes & Tubing'),
      ('spares', 'Spare Parts & Valves'),
      ('accessories', 'Accessories'),
    ];
    for (final (key, title) in categories) {
      final app = product('NEW-SKU-1', key, title, 'purifier.jpg').displayImageUrl;
      expect(app, 'catalog-sprite://${serverTile('NEW-SKU-1', key, title)}', reason: key);
    }
  });

  test('uploaded photos are used as they are, in the app and on share pages', () {
    final p = product('RO-FLT-CTO', 'filters', 'Filters', '/uploads/prod_1_2.jpg');
    expect(p.displayImageUrl, '/uploads/prod_1_2.jpg');
    expect(placeholders.contains('prod_1_2.jpg'), isFalse);
  });

  test('a full image URL saved in Admin is always shown as-is, even with a placeholder file name', () {
    const supabase =
        'https://abc.supabase.co/storage/v1/object/public/ro-product-images';
    for (final url in [
      '$supabase/booster-pumps/Max%20flow%20pump%201%20year%20warranty%20100%20gpd.jpg',
      '$supabase/membrane/membrane.jpg',
      'https://ro-mobileapp.onrender.com/purifier.jpg',
    ]) {
      expect(product('MUK-02', 'pumps', 'Booster Pumps', url).displayImageUrl, url);
      expect(product('RO-PMP-100', 'pumps', 'Booster Pumps', url).allImages, [url]);
    }
    // Bare demo names keep the built-in picture.
    expect(
      product('RO-PMP-100', 'pumps', 'Booster Pumps', 'cat_pump.jpg').displayImageUrl,
      startsWith('catalog-sprite://'),
    );
  });

  test('placeholder list matches the app', () {
    for (final img in placeholders) {
      expect(
        product('UNMAPPED', 'systems', 'RO Systems', img).displayImageUrl,
        startsWith('catalog-sprite://'),
        reason: img,
      );
    }
    expect(
      product('UNMAPPED', 'systems', 'RO Systems', 'tank.jpg').displayImageUrl,
      'tank.jpg',
    );
  });
}
