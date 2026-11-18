import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/core/network/api_client.dart';
import 'package:ro_wholesale_dealer_app/features/cart/presentation/providers/cart_provider.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/category_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/providers/product_provider.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/screens/categories_screen.dart';

class _EmptyCart extends CartNotifier {
  _EmptyCart() : super(ApiClient(), 'dealer', catalog: () => []);
  @override
  Future<void> refreshCart() async {}
}

const _categories = [
  CategoryModel(id: 'systems', name: 'RO Systems', imagePath: '', productCount: 2, description: 'Purifiers'),
  CategoryModel(id: 'membranes', name: 'Membranes', imagePath: '', productCount: 1, description: 'Membranes'),
  CategoryModel(id: 'filters', name: 'Filters & Cartridges', imagePath: '', productCount: 1, description: 'Filters'),
  CategoryModel(id: 'pumps', name: 'Booster Pumps', imagePath: '', productCount: 1, description: 'Pumps'),
  CategoryModel(id: 'pipes', name: 'Pipes & Tubing', imagePath: '', productCount: 1, description: 'Pipes'),
  CategoryModel(id: 'spares', name: 'Spare Parts & Valves', imagePath: '', productCount: 1, description: 'Spares'),
];

ProductModel _p(String id, String name, CategoryModel c) => ProductModel(
  id: id,
  name: name,
  sku: 'SKU-$id',
  categoryId: c.id,
  categoryName: c.name,
  brand: 'RO Wholesale',
  mrp: 1200,
  dealerPrice: 900,
  imageUrl: 'assets/images/RO_System.png',
  stockStatus: StockStatus.inStock,
  moq: 1,
);

final _products = [
  _p('s1', 'Commercial RO System 25 LPH', _categories[0]),
  _p('s2', 'Domestic RO System 10 L', _categories[0]),
  _p('m1', 'RO Membrane 75 GPD', _categories[1]),
  _p('f1', 'Sediment Filter 10 Inch', _categories[2]),
  _p('p1', 'RO Booster Pump 100 GPD', _categories[3]),
  _p('t1', 'PE Tubing 1/4 Inch', _categories[4]),
  _p('v1', 'RO Solenoid Valve 24 V', _categories[5]),
];

Finder _sidebarItem(String id) => find.byKey(ValueKey('category-sidebar-$id'));

Future<GlobalKey> _pump(WidgetTester tester, double width) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1300);
  addTearDown(tester.view.reset);
  final key = GlobalKey();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        catalogProductsProvider.overrideWith((ref) async => _products),
        catalogCategoriesProvider.overrideWith((ref) async => _categories),
        cartProvider.overrideWith((ref) => _EmptyCart()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(key: key, child: const CategoriesScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // Decode the bundled category photos (network URLs fall back to them).
  await tester.runAsync(() async {
    final ctx = tester.element(find.byType(CategoriesScreen));
    for (final f in ['RO_System.png', 'membrane.webp', 'filter.jpg', 'pumps.webp', 'tubes.jpg', 'spare_parts.jpg']) {
      await precacheImage(AssetImage('assets/images/$f'), ctx).catchError((_) {});
    }
  });
  await tester.pumpAndSettle();
  return key;
}

void main() {
  final previewDir = Platform.environment['PREVIEW_DIR'];
  final previewFont = Platform.environment['PREVIEW_FONT'];

  setUpAll(() async {
    if (previewFont != null && File(previewFont).existsSync()) {
      final loader = FontLoader('Roboto')
        ..addFont(Future.value(ByteData.sublistView(File(previewFont).readAsBytesSync())));
      await loader.load();
    }
  });

  for (final (label, width) in [
    ('desktop', 1440.0),
    ('tablet', 820.0),
    ('mobile', 390.0),
    ('narrow', 300.0),
  ]) {
    testWidgets('categories layout on $label', (tester) async {
      final key = await _pump(tester, width);
      expect(tester.takeException(), isNull);

      // Sidebar: every item same width & height, thumbnails centred on one
      // vertical line, and nothing past the sidebar edge.
      final ids = ['for_you', for (final c in _categories) c.id];
      final rects = [for (final id in ids) tester.getRect(_sidebarItem(id))];
      expect({for (final r in rects) r.width.round()}, hasLength(1), reason: 'equal width');
      expect({for (final r in rects.take(5)) r.height.round()}, hasLength(1), reason: 'equal height');
      final centres = {for (final r in rects) r.center.dx.round()};
      expect(centres, hasLength(1), reason: 'centred column');
      for (final id in ids.take(5)) {
        final texts = find.descendant(of: _sidebarItem(id), matching: find.byType(Text));
        for (final e in texts.evaluate()) {
          final r = tester.getRect(find.byWidget(e.widget));
          final item = tester.getRect(_sidebarItem(id));
          expect(r.left, greaterThanOrEqualTo(item.left), reason: 'label inside item');
          expect(r.right, lessThanOrEqualTo(item.right), reason: 'label inside item');
          expect(r.bottom, lessThanOrEqualTo(item.bottom + 0.5), reason: 'label not clipped');
        }
      }
      // Long names show on two lines, fully.
      expect(find.descendant(of: _sidebarItem('filters'), matching: find.text('Filters & Cartridges')), findsOneWidget);

      // Popular Store tiles fit inside the content area.
      for (final c in _categories) {
        final tile = find.byKey(ValueKey('popular-store-${c.id}'));
        if (tile.evaluate().isEmpty) continue;
        final r = tester.getRect(tile);
        expect(r.right, lessThanOrEqualTo(width + 0.5));
        expect(r.left, greaterThanOrEqualTo(rects.first.right - 0.5));
      }

      if (previewDir != null) {
        await tester.runAsync(() async {
          final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final img = await b.toImage();
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          File('$previewDir/categories_$label.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }

      // Selecting a category highlights it and shows its products.
      await tester.tap(_sidebarItem('pumps'));
      await tester.pumpAndSettle();
      final sem = tester.getSemantics(_sidebarItem('pumps'));
      expect(sem.hasFlag(ui.SemanticsFlag.isSelected), isTrue);
      expect(find.text('RO Booster Pump 100 GPD'), findsWidgets);
      // Short content starts at the top (was vertically centred before).
      expect(
        tester.getRect(find.text('1 Wholesale Items Available')).top,
        lessThan(240),
        reason: 'category content starts at the top',
      );
      expect(tester.takeException(), isNull);
      if (previewDir != null) {
        await tester.runAsync(() async {
          final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final img = await b.toImage();
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          File('$previewDir/categories_${label}_pumps.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }
    });
  }

  testWidgets('popular store tile opens its category; search still works', (tester) async {
    await _pump(tester, 1440);
    await tester.tap(find.byKey(const ValueKey('popular-store-membranes')));
    await tester.pumpAndSettle();
    expect(tester.getSemantics(_sidebarItem('membranes')).hasFlag(ui.SemanticsFlag.isSelected), isTrue);
    expect(find.text('RO Membrane 75 GPD'), findsWidgets);

    await tester.tap(find.byIcon(Icons.search_rounded).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'solenoid');
    await tester.pumpAndSettle();
    expect(find.text('RO Solenoid Valve 24 V'), findsWidgets);
    expect(find.text('RO Membrane 75 GPD'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
