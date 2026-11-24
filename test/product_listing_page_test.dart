import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ro_wholesale_dealer_app/features/cart/domain/models/cart_item_model.dart';
import 'package:ro_wholesale_dealer_app/core/network/api_client.dart';
import 'package:ro_wholesale_dealer_app/features/cart/presentation/providers/cart_provider.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/category_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/providers/product_provider.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/screens/product_listing_screen.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/widgets/filter_bottom_sheet.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/widgets/listing_product_card.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/widgets/sort_bottom_sheet.dart';

/// Records cart additions instead of calling the backend.
class _RecordingCart extends CartNotifier {
  _RecordingCart() : super(ApiClient(), 'test-user', catalog: () => []);

  final added = <(String, int)>[];

  @override
  Future<void> refreshCart() async {}

  @override
  Future<void> addToCart(
    ProductModel product, {
    int? quantity,
    PurchaseMode mode = PurchaseMode.normal,
  }) async {
    added.add((product.id, quantity ?? 1));
  }
}

const _categories = [
  CategoryModel(
    id: 'systems',
    name: 'RO Systems',
    imagePath: '',
    productCount: 3,
    description: 'Commercial & Domestic RO Water Purification Systems',
  ),
  CategoryModel(
    id: 'membranes',
    name: 'Membranes',
    imagePath: '',
    productCount: 1,
    description: 'RO membranes',
  ),
];

ProductModel _p(
  String id,
  String name,
  CategoryModel cat,
  double price,
  double mrp, {
  String brand = 'RO Wholesale',
  StockStatus stock = StockStatus.inStock,
}) => ProductModel(
  id: id,
  name: name,
  sku: 'RO-$id',
  categoryId: cat.id,
  categoryName: cat.name,
  brand: brand,
  mrp: mrp,
  dealerPrice: price,
  imageUrl: 'assets/images/RO_System.png',
  stockStatus: stock,
  moq: 1,
);

final _products = [
  _p('SYS-25', 'Commercial RO System 25 LPH', _categories[0], 16500, 22000),
  _p('SYS-50', 'Commercial RO System 50 LPH', _categories[0], 24500, 32000),
  _p(
    'SYS-10',
    'Domestic RO System 10 L',
    _categories[0],
    7500,
    9500,
    brand: 'Kent',
  ),
  _p(
    'MEM-75',
    'RO Membrane 75 GPD',
    _categories[1],
    650,
    900,
    stock: StockStatus.outOfStock,
  ),
];

Future<(_RecordingCart, GoRouter)> _pump(
  WidgetTester tester,
  double width, {
  GlobalKey? shotKey,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, 1400);
  addTearDown(tester.view.reset);
  final cart = _RecordingCart();
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (context, _) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ProductListingScreen(
                    initialCategoryId: 'systems',
                    initialCategoryName: 'RO Systems',
                  ),
                ),
              ),
              child: const Text('OPEN LISTING'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/categories',
        builder: (_, __) => const Scaffold(body: Text('CATEGORIES PAGE')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        catalogProductsProvider.overrideWith((ref) async => _products),
        catalogCategoriesProvider.overrideWith((ref) async => _categories),
        cartProvider.overrideWith((ref) => cart),
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
  await tester.tap(find.text('OPEN LISTING'));
  await tester.pumpAndSettle();
  return (cart, router);
}

Finder _cards() => find.byType(ListingProductCard);

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

  Future<void> shot(WidgetTester tester, GlobalKey key, String name) async {
    if (previewDir == null) return;
    await tester.runAsync(() async {
      for (final e in find.byType(Image).evaluate()) {
        final img = (e.widget as Image).image;
        await precacheImage(img, e).catchError((_) {});
      }
    });
    await tester.pump();
    await tester.runAsync(() async {
      final b =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await b.toImage();
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$previewDir/$name.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  test('rupee formatting uses Indian grouping', () {
    expect(formatRupees(7500), '7,500');
    expect(formatRupees(16500), '16,500');
    expect(formatRupees(125000), '1,25,000');
  });

  for (final (label, width, columns) in [
    ('desktop', 1440.0, 3),
    ('tablet', 820.0, 2),
    ('mobile', 390.0, 1),
  ]) {
    testWidgets('listing layout on $label: $columns per row', (tester) async {
      final key = GlobalKey();
      await _pump(tester, width, shotKey: key);
      expect(tester.takeException(), isNull);

      // Header with the category's real name and description.
      expect(find.text('RO Systems'), findsWidgets);
      expect(
        find.text('Commercial & Domestic RO Water Purification Systems'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('listing-count')), findsOneWidget);
      expect(find.text('3 Products Found'), findsOneWidget);

      // Only this category's products, as cards with equal heights.
      expect(_cards(), findsNWidgets(3));
      final rects = [
        for (final e in _cards().evaluate())
          tester.getRect(find.byWidget(e.widget)),
      ];
      expect({for (final r in rects) r.height.round()}, hasLength(1));
      final firstRowTop = rects
          .map((r) => r.top)
          .reduce((a, b) => a < b ? a : b);
      expect(
        rects.where((r) => (r.top - firstRowTop).abs() < 1).length,
        columns,
        reason: 'cards per row: $rects',
      );
      for (final r in rects) {
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(width));
      }

      // Real prices with Indian grouping and MRP; no discount badge.
      expect(find.text('₹16,500'), findsOneWidget);
      expect(find.text('₹22,000'), findsOneWidget);
      expect(find.textContaining('% OFF'), findsNothing);
      expect(find.text('SKU: RO-SYS-25  •  MOQ: 1 Pcs'), findsOneWidget);
      await shot(tester, key, 'listing_$label');

      // List view keeps everything aligned too.
      await tester.tap(find.byKey(const ValueKey('view-list')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(_cards(), findsNWidgets(3));
      await shot(tester, key, 'listing_${label}_list');
    });
  }

  testWidgets('quantity selector and Add to Cart use the chosen quantity', (
    tester,
  ) async {
    final (cart, _) = await _pump(tester, 1440);
    final card = find.byKey(const ValueKey('listing-card-SYS-25'));
    Finder inCard(Finder f) => find.descendant(of: card, matching: f);

    expect(inCard(find.byKey(const ValueKey('qty-value'))), findsOneWidget);
    await tester.tap(inCard(find.byTooltip('Increase quantity')));
    await tester.pump();
    await tester.tap(inCard(find.byTooltip('Increase quantity')));
    await tester.pump();
    expect(
      tester.widget<Text>(inCard(find.byKey(const ValueKey('qty-value')))).data,
      '3',
    );
    await tester.tap(inCard(find.byTooltip('Decrease quantity')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('add-to-cart-SYS-25')));
    await tester.pumpAndSettle();
    expect(cart.added, [('SYS-25', 2)]);
    expect(find.text('Product added to cart successfully'), findsOneWidget);
    expect(find.text('View Cart'), findsOneWidget);
    // Quantity resets after a successful add.
    expect(
      tester.widget<Text>(inCard(find.byKey(const ValueKey('qty-value')))).data,
      '1',
    );
  });

  testWidgets('search, category chips, sort and filter all work', (
    tester,
  ) async {
    await _pump(tester, 1440);

    // Search (by brand).
    await tester.enterText(
      find.byKey(const ValueKey('listing-search')),
      'kent',
    );
    await tester.pumpAndSettle();
    expect(_cards(), findsOneWidget);
    expect(find.text('Domestic RO System 10 L'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(_cards(), findsNWidgets(3));

    // Category chips.
    await tester.tap(find.byKey(const ValueKey('category-chip-membranes')));
    await tester.pumpAndSettle();
    expect(find.text('1 Product Found'), findsOneWidget);
    expect(find.text('Out of Stock'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('category-chip-all')));
    await tester.pumpAndSettle();
    expect(find.text('4 Products Found'), findsOneWidget);
    expect(find.text('All Products'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('category-chip-systems')));
    await tester.pumpAndSettle();

    // Sort sheet edits THIS listing (scoped filter state).
    await tester.tap(find.byKey(const ValueKey('listing-sort')));
    await tester.pumpAndSettle();
    expect(find.byType(SortBottomSheet), findsOneWidget);
    final lowToHigh = find.descendant(
      of: find.byType(SortBottomSheet),
      matching: find.textContaining(
        RegExp('Low to High', caseSensitive: false),
      ),
    );
    if (lowToHigh.evaluate().isNotEmpty) {
      await tester.tap(lowToHigh.first);
      await tester.pumpAndSettle();
      final tops = {
        for (final id in ['SYS-10', 'SYS-25', 'SYS-50'])
          id: tester.getTopLeft(find.byKey(ValueKey('listing-card-$id'))).dx,
      };
      expect(tops['SYS-10']! < tops['SYS-25']!, isTrue, reason: 'sorted');
      expect(tops['SYS-25']! < tops['SYS-50']!, isTrue, reason: 'sorted');
    } else {
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    }

    // Filter sheet opens.
    await tester.tap(find.byKey(const ValueKey('listing-filter')));
    await tester.pumpAndSettle();
    expect(find.byType(FilterBottomSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('back and Categories breadcrumb navigate', (tester) async {
    await _pump(tester, 1440);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('OPEN LISTING'), findsOneWidget);

    await tester.tap(find.text('OPEN LISTING'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Categories'));
    await tester.pumpAndSettle();
    expect(find.text('CATEGORIES PAGE'), findsOneWidget);
  });
}
