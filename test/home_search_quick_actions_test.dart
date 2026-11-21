import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ro_wholesale_dealer_app/features/home/presentation/screens/home_screen.dart';
import 'package:ro_wholesale_dealer_app/features/home/presentation/widgets/home_search_bar.dart';
import 'package:ro_wholesale_dealer_app/features/home/presentation/widgets/hero_carousel/hero_banner_carousel.dart';
import 'package:ro_wholesale_dealer_app/features/home/presentation/widgets/quick_action_tile.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/category_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/providers/product_provider.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/screens/product_details_screen.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/widgets/filter_bottom_sheet.dart';

const _categories = [
  CategoryModel(
    id: 'pumps',
    name: 'RO Pumps',
    imagePath: '',
    productCount: 2,
    description: 'Booster pumps',
  ),
  CategoryModel(
    id: 'membranes',
    name: 'Membranes',
    imagePath: '',
    productCount: 1,
    description: 'RO membranes',
  ),
  CategoryModel(
    id: 'filters',
    name: 'Filters',
    imagePath: '',
    productCount: 7,
    description: 'Cartridges',
  ),
];

ProductModel _p(
  String id,
  String name,
  CategoryModel cat, {
  String brand = 'Neero+',
  String sku = '',
}) => ProductModel(
  id: id,
  name: name,
  sku: sku.isEmpty ? 'SKU-$id' : sku,
  categoryId: cat.id,
  categoryName: cat.name,
  brand: brand,
  mrp: 1500,
  dealerPrice: 900,
  imageUrl: 'assets/images/banners_cutout/filter.png',
  stockStatus: StockStatus.inStock,
  moq: 5,
);

final _products = [
  _p('1', '75 GPD Booster Pump', _categories[0], brand: 'Kemflo'),
  _p('2', '100 GPD Booster Pump', _categories[0], sku: 'PMP-100'),
  _p('3', 'Vontron 80 GPD Membrane', _categories[1], brand: 'Vontron'),
  for (var i = 0; i < 7; i++)
    _p('f$i', 'Carbon Filter Cartridge $i', _categories[2]),
];

Future<GoRouter> _pumpHome(
  WidgetTester tester,
  double width,
  Key shotKey,
) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, 1200);
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
      for (final page in [
        'products',
        'orders',
        'profile',
        'cart',
        'bulk-orders',
      ])
        GoRoute(
          path: '/$page',
          builder: (_, __) =>
              Scaffold(body: Center(child: Text('${page.toUpperCase()} PAGE'))),
        ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        catalogProductsProvider.overrideWith((ref) async => _products),
        catalogCategoriesProvider.overrideWith((ref) async => _categories),
      ],
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        routerConfig: router,
        builder: (context, child) =>
            RepaintBoundary(key: shotKey, child: child),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return router;
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const ValueKey('home-search-field')), text);
  await tester.pump();
}

Future<void> _settleDebounce(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 300)); // AnimatedSize
}

Finder _resultNames() => find.descendant(
  of: find.byKey(const ValueKey('home-search-results')),
  matching: find.byWidgetPredicate(
    (w) =>
        w is Text &&
        (w.data ?? '').contains(RegExp(r'Pump|Membrane|Filter Cartridge')),
  ),
);

/// Text inside the search results panel only (product grids repeat names).
Finder _inResults(String text) => find.descendant(
  of: find.byKey(const ValueKey('home-search-results')),
  matching: find.text(text),
);

void main() {
  final previewDir = Platform.environment['PREVIEW_DIR'];
  final previewFont = Platform.environment['PREVIEW_FONT'];

  setUpAll(() async {
    if (previewFont != null && File(previewFont).existsSync()) {
      final loader = FontLoader('Roboto')
        ..addFont(
          Future.value(
            ByteData.sublistView(File(previewFont).readAsBytesSync()),
          ),
        );
      await loader.load();
    }
  });

  Future<void> shot(WidgetTester tester, Key key, String name) async {
    if (previewDir == null) return;
    await tester.runAsync(() async {
      final b =
          (key as GlobalKey).currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final img = await b.toImage();
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$previewDir/$name.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  for (final (label, width) in [
    ('desktop', 1280.0),
    ('tablet', 800.0),
    ('mobile', 390.0),
  ]) {
    testWidgets('search + quick actions layout and spacing on $label', (
      tester,
    ) async {
      final key = GlobalKey();
      await _pumpHome(tester, width, key);
      expect(tester.takeException(), isNull);

      expect(find.text(HomeSearchBar.placeholder), findsOneWidget);
      expect(find.byType(QuickActionTile), findsNWidgets(4));

      // Desktop: one row of four. Tablet & phone: 2 x 2 grid.
      final tops = {
        for (final l in [
          'Bulk Order',
          'Track Orders',
          'GST Invoice',
          'Credit Limit',
        ])
          tester.getRect(find.widgetWithText(QuickActionTile, l)).top.round(),
      };
      expect(tops.length, width >= 900 ? 1 : 2, reason: 'rows of cards');

      // Equal card heights within a row.
      final heights = {
        for (final t in find.byType(QuickActionTile).evaluate())
          tester.getSize(find.byWidget(t.widget)).height.round(),
      };
      expect(heights.length, 1, reason: 'consistent card height');

      // Spacing: search -> cards and cards -> slider are 24-32 px.
      final search = tester.getRect(find.byType(HomeSearchBar));
      final cards = find
          .byType(QuickActionTile)
          .evaluate()
          .map((e) => tester.getRect(find.byWidget(e.widget)));
      final cardsTop = cards.map((r) => r.top).reduce((a, b) => a < b ? a : b);
      final cardsBottom = cards
          .map((r) => r.bottom)
          .reduce((a, b) => a > b ? a : b);
      final slider = tester.getRect(find.byType(HeroBannerCarousel));
      final gap1 = cardsTop - search.bottom;
      final gap2 = slider.top - cardsBottom;
      expect(gap1, inInclusiveRange(24, 32), reason: 'search -> cards');
      expect(gap2, inInclusiveRange(24, 32), reason: 'cards -> slider');

      // Nothing overflows the screen horizontally.
      for (final r in [search, ...cards]) {
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(width));
      }
      await shot(tester, key, 'top_$label');

      // Live search preview screenshot.
      await _type(tester, 'pump');
      await _settleDebounce(tester);
      expect(tester.takeException(), isNull);
      await shot(tester, key, 'search_$label');
    });
  }

  testWidgets('search: debounce, live results, empty state, clear, view all', (
    tester,
  ) async {
    await _pumpHome(tester, 1280, GlobalKey());

    // While typing: loading indicator, no results yet (debounced).
    await _type(tester, 'pump');
    expect(find.byKey(const ValueKey('home-search-loading')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-search-searching')), findsOneWidget);
    await _settleDebounce(tester);
    expect(find.byKey(const ValueKey('home-search-loading')), findsNothing);
    expect(find.text('2 products found'), findsOneWidget);
    expect(_inResults('75 GPD Booster Pump'), findsOneWidget);
    expect(_inResults('100 GPD Booster Pump'), findsOneWidget);

    // By category name, brand and SKU.
    await _type(tester, 'membranes');
    await _settleDebounce(tester);
    expect(_inResults('Vontron 80 GPD Membrane'), findsOneWidget);
    await _type(tester, 'kemflo');
    await _settleDebounce(tester);
    expect(find.text('1 product found'), findsOneWidget);
    expect(_inResults('75 GPD Booster Pump'), findsOneWidget);
    await _type(tester, 'PMP-100');
    await _settleDebounce(tester);
    expect(_inResults('100 GPD Booster Pump'), findsOneWidget);

    // Many results: preview first 5, "View all" shows every match.
    await _type(tester, 'filter');
    await _settleDebounce(tester);
    expect(find.text('7 products found'), findsOneWidget);
    expect(_resultNames(), findsNWidgets(5));
    await tester.tap(find.text('View all 7'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Show less'), findsOneWidget);
    // The full list scrolls inside the panel: the last match is reachable.
    await tester.scrollUntilVisible(
      _inResults('Carbon Filter Cartridge 6'),
      80,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('home-search-results')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(_inResults('Carbon Filter Cartridge 6'), findsOneWidget);

    // Empty state with real category suggestions.
    await _type(tester, 'zzzz');
    await _settleDebounce(tester);
    expect(find.byKey(const ValueKey('home-search-empty')), findsOneWidget);
    expect(find.text('No products match "zzzz"'), findsOneWidget);
    await tester.tap(find.widgetWithText(ActionChip, 'Membranes'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_inResults('Vontron 80 GPD Membrane'), findsOneWidget);

    // Clear removes the query and the results panel.
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('home-search-results')), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('home-search-field')))
          .controller!
          .text,
      isEmpty,
    );

    // Tapping a result opens its product page.
    await _type(tester, 'vontron');
    await _settleDebounce(tester);
    await tester.tap(_inResults('Vontron 80 GPD Membrane'));
    await tester.pumpAndSettle();
    expect(find.byType(ProductDetailsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filter button opens the catalogue filter sheet', (tester) async {
    // 800 px: the shared Products filter sheet's header rows are wider than a
    // 390 px phone only with the test font (fine with real fonts).
    await _pumpHome(tester, 800, GlobalKey());
    await tester.tap(find.byKey(const ValueKey('home-search-filter')));
    await tester.pumpAndSettle();
    expect(find.byType(FilterBottomSheet), findsOneWidget);
  });

  for (final (action, page) in [
    // Bulk Orders has its own page (not the normal Categories page).
    ('Bulk Order', 'BULK-ORDERS PAGE'),
    ('Track Orders', 'ORDERS PAGE'),
    ('GST Invoice', 'ORDERS PAGE'),
    ('Credit Limit', 'PROFILE PAGE'),
  ]) {
    testWidgets('quick action "$action" opens ${page.toLowerCase()}', (
      tester,
    ) async {
      await _pumpHome(tester, 390, GlobalKey());
      // Tap the card body (not just the text): the whole card is clickable.
      final card = tester.getRect(find.widgetWithText(QuickActionTile, action));
      await tester.tapAt(card.bottomRight - const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text(page), findsOneWidget);
    });
  }
}
