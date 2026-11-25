import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/category_price_view.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/category_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_share.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/product_share_category.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/widgets/product_share_card.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/widgets/product_share_sheet.dart';

// The live categories (key_name -> id, title).
const categories = [
  CategoryModel(id: 'systems', databaseId: 'CAT_SYS', name: 'RO Systems', imagePath: '', productCount: 0, description: ''),
  CategoryModel(id: 'membranes', databaseId: 'CAT_MEM', name: 'Membranes', imagePath: '', productCount: 0, description: ''),
  CategoryModel(id: 'filters', databaseId: 'CAT_FLT', name: 'Filters & Cartridges', imagePath: '', productCount: 0, description: ''),
  CategoryModel(id: 'pumps', databaseId: 'CAT_PMP', name: 'Booster Pumps', imagePath: '', productCount: 0, description: ''),
  CategoryModel(id: 'pipes', databaseId: 'CAT_PIP', name: 'Pipes & Tubing', imagePath: '', productCount: 0, description: ''),
  CategoryModel(id: 'spares', databaseId: 'CAT_SPR', name: 'Spare Parts & Valves', imagePath: '', productCount: 0, description: ''),
  CategoryModel(id: 'cabinets', databaseId: 'CAT_CAB', name: 'Cabinet', imagePath: '', productCount: 0, description: ''),
];

/// A product as /api/products returns it (saved category key + joined title).
ProductModel api(String sku, String name, String key, String? title) =>
    ProductModel.fromJson({
      'id': 'PDF_$sku',
      'sku': sku,
      'name': name,
      'category_key': key,
      'category_id': 'CAT_X',
      if (title != null) 'category_name': title,
      'price': 100,
      'mrp': 200,
      'img': 'https://abc.supabase.co/storage/v1/object/public/ro-product-images/x/$sku.jpg',
    });

String shareLine(ProductModel p) => productShareText(productForSharing(p, categories))
    .split('\n')
    .firstWhere((l) => l.startsWith('Category:'), orElse: () => '(no category line)');

void main() {
  test('each product is shared with its own saved category', () {
    final cases = {
      api('RO-SYS-25', 'RO System 25 LPH', 'systems', 'RO Systems'): 'Category: RO Systems',
      api('CAB-11', 'Aqua roma cherry', 'cabinets', 'Cabinet'): 'Category: Cabinet',
      api('DOM-29', 'Otayo 80 gpd membrane', 'membranes', 'Membranes'): 'Category: Membranes',
      api('MUK-02', 'Max flow pump', 'pumps', 'Booster Pumps'): 'Category: Booster Pumps',
      api('DOM-09', 'SMPS 24V 1.5A', 'spares', 'Spare Parts & Valves'): 'Category: Spare Parts & Valves',
    };
    cases.forEach((p, expected) => expect(shareLine(p), expected, reason: p.sku));
  });

  test('the category comes from the saved category, not the product name or SKU', () {
    // A Cabinet-sounding name saved under RO Systems is shared as RO Systems.
    final p = api('CAB-LIKE', 'Aqua cabinet membrane pump', 'systems', null);
    expect(shareCategoryName(p, categories), 'RO Systems');
    // Saved category given by database id instead of key.
    final byId = ProductModel.fromJson({'id': 'x', 'sku': 'S1', 'name': 'n', 'category_id': 'CAT_PMP', 'price': 1});
    expect(shareCategoryName(byId, categories), 'Booster Pumps');
  });

  test('no joined title (e.g. cart data): resolved from the saved key, never the raw key', () {
    final p = api('RO-SYS-10L', 'RO 10L', 'systems', null);
    expect(p.categoryName, 'systems', reason: 'the model falls back to the key');
    expect(shareCategoryName(p, categories), 'RO Systems');
    expect(shareCategoryName(p, const []), '', reason: 'without categories: left out, not "systems"');
  });

  test('unknown or missing category: the share leaves the category out', () {
    expect(shareLine(api('X-1', 'Unknown', 'retired_category', null)), '(no category line)');
    final none = ProductModel.fromJson({'id': 'y', 'sku': 'Y', 'name': 'n', 'price': 1});
    expect(shareCategoryName(none, categories), '');
    expect(productShareText(productForSharing(none, categories)).contains('Category:'), isFalse);
  });

  test('everything else in the share is unchanged', () {
    final p = api('MUK-02', 'Max flow pump', 'pumps', 'Booster Pumps');
    final shared = productForSharing(p, categories);
    expect(shared.name, p.name);
    expect(shared.sku, p.sku);
    expect(shared.mrp, p.mrp);
    expect(shared.imageUrl, p.imageUrl);
    expect(shared.id, p.id);
    expect(identical(shared, p), isTrue, reason: 'already correct: same object');
    expect(whatsAppShareText(shared), contains('Category: Booster Pumps'));
    expect(productShareText(shared), contains('Product Name: Max flow pump'));
  });

  group('share category follows the page the product is shared from', () {
    final cabinet = api('CAB-11', 'Aqua roma cherry', 'cabinets', 'Cabinet');
    final roSystem = api('RO-SYS-25', 'RO System 25 LPH', 'systems', 'RO Systems');
    final membrane = api('DOM-29', 'Otayo 80 gpd membrane', 'membranes', 'Membranes');
    String line(ProductModel p, ProductPriceView view) =>
        whatsAppShareText(productForSharing(p, categories, view: view), view: view)
            .split('\n')
            .firstWhere((l) => l.startsWith('Category:'), orElse: () => '(none)');

    test('same Cabinet product: RO Systems page vs Cabinet page', () {
      expect(line(cabinet, ProductPriceView.roSystems), 'Category: RO Systems');
      expect(line(cabinet, ProductPriceView.cabinet), 'Category: Cabinet');
      expect(line(cabinet, ProductPriceView.standard), 'Category: Cabinet',
          reason: 'other pages (search, All Products): saved category');
    });

    test('genuine RO System from the RO Systems page / Best Sellers', () {
      expect(line(roSystem, ProductPriceView.roSystems), 'Category: RO Systems');
      expect(line(roSystem, ProductPriceView.standard), 'Category: RO Systems');
    });

    test('a page never claims products it does not list', () {
      expect(line(membrane, ProductPriceView.roSystems), 'Category: Membranes');
      expect(line(membrane, ProductPriceView.cabinet), 'Category: Membranes');
      expect(line(roSystem, ProductPriceView.cabinet), 'Category: RO Systems');
    });

    test('the context name comes from the category record, not a constant', () {
      final renamed = [
        for (final c in categories)
          c.id == 'systems'
              ? const CategoryModel(id: 'systems', databaseId: 'CAT_SYS', name: 'RO Systems', imagePath: '', productCount: 0, description: '')
              : c.id == 'cabinets'
                  ? const CategoryModel(id: 'cabinets', databaseId: 'CAT_CAB', name: 'Cabinets', imagePath: '', productCount: 0, description: '')
                  : c,
      ];
      expect(shareCategoryName(cabinet, renamed, view: ProductPriceView.cabinet), 'Cabinets');
    });

    test('the share card uses the same category; no product link anywhere', () {
      final shared = productForSharing(cabinet, categories, view: ProductPriceView.roSystems);
      expect(shared.categoryName, 'RO Systems', reason: 'card image reads categoryName');
      expect(shared.cabinetPrice, cabinet.cabinetPrice);
      expect(shared.dealerPrice, cabinet.dealerPrice);
      for (final view in ProductPriceView.values) {
        final s = productForSharing(cabinet, categories, view: view);
        for (final text in [
          whatsAppShareText(s, view: view),
          productShareText(s, view: view),
          shareCardText(s, view: view).join(' '),
          whatsAppShareUri(s, view: view).queryParameters['text']!,
        ]) {
          expect(text, isNot(contains('http')), reason: '$view');
          expect(text, isNot(contains('Product Link')), reason: '$view');
          expect(text, isNot(contains('share/products')), reason: '$view');
        }
      }
    });
  });

  group('share price follows the page', () {
    final cabinet = ProductModel.fromJson({
      'id': 'PDF_CAB_15', 'sku': 'CAB-15', 'name': 'Aqua 2090 -premium gray602',
      'category_key': 'cabinets', 'category_name': 'Cabinet',
      'price': 4650, 'mrp': 13500, 'cabinet_price': 1850,
    });
    final roSystem = api('RO-SYS-25', 'RO System 25 LPH', 'systems', 'RO Systems');

    test('Cabinet page: Cabinet Price only, never MRP or Dealer Price', () {
      const view = ProductPriceView.cabinet;
      final shared = productForSharing(cabinet, categories, view: view);
      for (final text in [
        whatsAppShareText(shared, view: view),
        productShareText(shared, view: view),
        shareCardText(shared, view: view).join('\n'),
      ]) {
        expect(text, contains('Cabinet Price'));
        expect(text, contains('₹1,850'));
        expect(text, isNot(contains('MRP')));
        expect(text, isNot(contains('13,500')));
        expect(text, isNot(contains('4,650')), reason: 'no Dealer Price');
      }
      expect(sharePrice(shared, view: view)!.label, 'Cabinet Price');
    });

    test('RO Systems page, Search / All Products: MRP only', () {
      for (final view in [ProductPriceView.roSystems, ProductPriceView.standard]) {
        final text = whatsAppShareText(cabinet, view: view);
        expect(text, contains('MRP: ₹13,500'));
        expect(text, isNot(contains('1,850')));
        expect(text, isNot(contains('4,650')));
        expect(shareCardText(cabinet, view: view), containsAll(['MRP', '₹13,500']));
      }
      expect(whatsAppShareText(roSystem, view: ProductPriceView.roSystems), contains('MRP: ₹200'));
      expect(sharePrice(roSystem, view: ProductPriceView.cabinet)!.label, 'MRP',
          reason: 'no Cabinet Price saved: MRP');
    });

    test('Search / All Products keep the saved category', () {
      expect(shareCategoryName(cabinet, categories), 'Cabinet');
      expect(shareCategoryName(roSystem, categories), 'RO Systems');
    });
  });

  test('a product whose image fails still gets a share card (water-drop placeholder)', () async {
    final card = await buildProductShareCardFile(
      api('MUK-24', '25 LPH Machine', 'systems', 'RO Systems'),
      null,
      ProductPriceView.roSystems,
    );
    expect(card.mimeType, 'image/png');
    expect(card.bytes.take(4), [0x89, 0x50, 0x4E, 0x47]);
    final notAnImage = await renderProductShareCard(
      api('MUK-25', '50 LPH Machine', 'systems', 'RO Systems'),
      Uint8List.fromList([1, 2, 3, 4]),
    );
    expect(notAnImage.take(4), [0x89, 0x50, 0x4E, 0x47]);
  });
}

