import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ro_wholesale_dealer_app/core/network/api_client.dart';
import 'package:ro_wholesale_dealer_app/features/bulk_orders/domain/bulk_catalog.dart';
import 'package:ro_wholesale_dealer_app/features/bulk_orders/presentation/screens/bulk_orders_screen.dart';
import 'package:ro_wholesale_dealer_app/features/bulk_orders/presentation/screens/bulk_product_details_screen.dart';
import 'package:ro_wholesale_dealer_app/features/cart/domain/models/cart_item_model.dart';
import 'package:ro_wholesale_dealer_app/features/cart/domain/order_pricing.dart';
import 'package:ro_wholesale_dealer_app/features/cart/presentation/providers/cart_provider.dart';
import 'package:ro_wholesale_dealer_app/features/cart/presentation/screens/cart_screen.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/category_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/providers/product_provider.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/widgets/listing_product_card.dart';

class _RecordingCart extends CartNotifier {
  _RecordingCart() : super(ApiClient(), 'test-user', catalog: () => []);
  final added = <(String, int, PurchaseMode)>[];
  @override
  Future<void> refreshCart() async {}
  @override
  Future<void> addToCart(
    ProductModel product, {
    int? quantity,
    PurchaseMode mode = PurchaseMode.normal,
  }) async {
    added.add((product.id, quantity ?? 1, mode));
  }
}

CategoryModel _cat(String id, String dbId, String name) => CategoryModel(
  id: id,
  databaseId: dbId,
  name: name,
  imagePath: '',
  productCount: 0,
  description: '',
);

final _categories = [
  _cat('systems', 'CAT_SYS', 'RO Systems'),
  _cat('membranes', 'CAT_MEM', 'Membranes'),
  _cat('filters', 'CAT_FLT', 'Filters & Cartridges'),
  _cat('pumps', 'CAT_PMP', 'Booster Pumps'),
  _cat('pipes', 'CAT_PIP', 'Pipes & Tubing'),
  _cat('spares', 'CAT_SPR', 'Spare Parts & Valves'),
  _cat('cabinets', 'CAT_CAB', 'Cabinet'),
];

ProductModel _p(
  String id,
  String name,
  String cat,
  double unit,
  double mrp, {
  double? bulk,
  int? min,
  int? step,
  String? label,
}) => ProductModel(
  id: id,
  name: name,
  sku: id,
  categoryId: cat,
  categoryName: cat,
  brand: '',
  mrp: mrp,
  dealerPrice: unit,
  bulkPrice: bulk,
  bulkMinQty: min,
  bulkStep: step,
  bulkPackLabel: label,
  imageUrl: '',
  stockStatus: StockStatus.inStock,
  moq: 1,
);

// Cruze gold inline (Domestic PDF: 80 / 77 (42 PCS) / 590) and a Mukhil item
// (UNIT 1000, BOX 980, Mini qty 10 nos), plus products without bulk offers.
final _cruze = _p(
  'DOM-01',
  'Cruze gold inline',
  'filters',
  80,
  590,
  bulk: 77,
  min: 42,
  step: 42,
  label: '42 PCS',
);
final _copper = _p(
  'DOM-02',
  '10" Copper Cartridge',
  'filters',
  180,
  1750,
  bulk: 170,
  min: 50,
  step: 50,
  label: '50 NOS',
);
final _pipe = _p(
  'MUK-05',
  'Ro pipe 3/8 100mtr white',
  'pipes',
  1000,
  2800,
  bulk: 980,
  min: 10,
  step: 1,
  label: '10 NOS',
);
final _plainFilter = _p('F-1', 'Plain Filter', 'filters', 100, 200);
final _pump = _p(
  'P-1',
  'Booster Pump',
  'pumps',
  1500,
  2200,
  bulk: 1400,
  min: 10,
  step: 1,
  label: '10 NOS',
);
final _products = [_cruze, _copper, _pipe, _plainFilter, _pump];

late GoRouter _router;

Future<_RecordingCart> _pump_(
  WidgetTester tester,
  double width, {
  String location = '/bulk-orders',
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 2400);
  addTearDown(tester.view.reset);
  final cart = _RecordingCart();
  final router = _router = GoRouter(
    initialLocation: location,
    routes: [
      // Same routes as the app (app_router.dart).
      GoRoute(
        path: '/bulk-orders',
        builder: (_, state) => BulkOrdersScreen(
          initialCategoryId: state.uri.queryParameters['category'],
        ),
        routes: [
          GoRoute(
            path: BulkProductDetailsScreen.routePath,
            builder: (_, state) => BulkProductDetailsScreen(
              productId: state.pathParameters['id']!,
              categoryId: state.uri.queryParameters['category'],
            ),
          ),
        ],
      ),
      GoRoute(path: '/home', builder: (_, __) => const Text('HOME')),
      GoRoute(path: '/cart', builder: (_, __) => const Text('CART')),
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
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return cart;
}

String _text(WidgetTester tester, String key) {
  final w = tester.widget(find.byKey(ValueKey(key)));
  if (w is Text) return w.data ?? w.textSpan!.toPlainText();
  // Rows (label + value): their texts joined by a space.
  return tester
      .widgetList<RichText>(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(RichText),
        ),
      )
      .map((t) => t.text.toPlainText().trim())
      // Icons are drawn as private-use glyphs: not part of the text.
      .where((t) => t.runes.any((r) => r < 0xE000 || r > 0xF8FF))
      .join(' ');
}

void main() {
  test('only the four Bulk categories, in order', () {
    expect(bulkCategories(_categories).map((c) => c.id), [
      'membranes',
      'filters',
      'pipes',
      'spares',
    ]);
    expect(bulkProductsIn(_categories[2], _products).map((p) => p.id), [
      'DOM-02',
      'DOM-01',
    ]);
  });

  test('cart line prices by mode; totals follow', () {
    const normal = CartItemModel(product: _dummy, quantity: 2);
    final bulk = CartItemModel(
      product: _cruze,
      quantity: 84,
      mode: PurchaseMode.bulk,
    );
    final plain = CartItemModel(product: _cruze, quantity: 3);
    expect(bulk.unitPrice, 77);
    expect(bulk.totalPrice, 84 * 77);
    expect(plain.unitPrice, 80, reason: 'normal purchase keeps Dealer Price');
    expect(normal.totalPrice, 20);
    final totals = CartState(items: [bulk, plain])
        .totals(PricingRules.fallback);
    expect(totals.subtotal, 84 * 77 + 3 * 80);
    // Dealer discount on the normal line only (bulk lines are excluded).
    expect(
      totals.discount,
      closeTo(
        3 * 80 * PricingRules.fallback.dealerDiscountPercent / 100,
        0.001,
      ),
    );
    expect(CartState(items: [bulk]).totals(PricingRules.fallback).discount, 0);
    expect(PurchaseMode.fromApi('bulk'), PurchaseMode.bulk);
    expect(PurchaseMode.fromApi(null), PurchaseMode.normal);
  });

  test('product bulk rules', () {
    expect(_cruze.hasBulkOffer, isTrue);
    expect(_cruze.bulkMinimumOrderValue, 3234);
    expect([42, 84, 126].every(_cruze.isValidBulkQuantity), isTrue);
    expect([1, 41, 43, 50].any(_cruze.isValidBulkQuantity), isFalse);
    expect([10, 11, 12].every(_pipe.isValidBulkQuantity), isTrue);
    expect(_pipe.isValidBulkQuantity(9), isFalse);
    expect(_plainFilter.hasBulkOffer, isFalse);
  });

  for (final width in [1400.0, 390.0]) {
    testWidgets('Bulk Orders page ($width)', (tester) async {
      final cart = await _pump_(tester, width);
      // Only the four Bulk categories (no All Products, RO Systems, Cabinet,
      // Booster Pumps).
      for (final id in ['membranes', 'filters', 'pipes', 'spares']) {
        expect(find.byKey(ValueKey('bulk-category-$id')), findsOneWidget);
      }
      for (final id in ['systems', 'pumps', 'cabinets']) {
        expect(find.byKey(ValueKey('bulk-category-$id')), findsNothing);
      }
      expect(find.text('All Products'), findsNothing);
      // First category with offers: Filters (2 bulk products; the plain one
      // is not listed).
      expect(
        find.text('2 Bulk Products in Filters & Cartridges'),
        findsOneWidget,
      );
      expect(find.text('Plain Filter'), findsNothing);

      // Cruze gold inline: bulk price only.
      expect(_text(tester, 'bulk-price-DOM-01'), '₹77 / piece');
      expect(_text(tester, 'bulk-min-DOM-01'), 'Minimum Pack 42 PCS');
      expect(
        _text(tester, 'bulk-min-value-DOM-01'),
        'Minimum Order Value ₹3,234',
      );
      expect(_text(tester, 'bulk-step-DOM-01'), 'Increment +42 (1 pack)');
      expect(find.text('Wholesale prices for bulk purchases.'), findsOneWidget);
      expect(find.text('₹80'), findsNothing, reason: 'no Unit/Dealer Price');
      expect(find.textContaining('590'), findsNothing, reason: 'no MRP');
      expect(find.textContaining('% OFF'), findsNothing);

      // Stepper: starts at 42, minus disabled, plus adds 42.
      String qty() => _text(tester, 'bulk-qty-DOM-01');
      expect(qty(), '42');
      await tester.ensureVisible(
        find.byKey(const ValueKey('bulk-minus-DOM-01')),
      );
      await tester.tap(find.byKey(const ValueKey('bulk-minus-DOM-01')));
      await tester.pump();
      expect(qty(), '42', reason: 'cannot go below one pack');
      await tester.tap(find.byKey(const ValueKey('bulk-plus-DOM-01')));
      await tester.pump();
      expect(qty(), '84');
      expect(_text(tester, 'bulk-total-DOM-01'), '₹6,468');
      await tester.tap(find.byKey(const ValueKey('bulk-plus-DOM-01')));
      await tester.pump();
      expect(qty(), '126');
      await tester.tap(find.byKey(const ValueKey('bulk-minus-DOM-01')));
      await tester.pump();
      expect(qty(), '84');
      await tester.tap(find.byKey(const ValueKey('bulk-add-DOM-01')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(cart.added.single, ('DOM-01', 84, PurchaseMode.bulk));
      expect(qty(), '42', reason: 'resets to one pack after adding');
      // Copper: packs of 50.
      expect(_text(tester, 'bulk-qty-DOM-02'), '50');
      await tester.ensureVisible(
        find.byKey(const ValueKey('bulk-plus-DOM-02')),
      );
      await tester.tap(find.byKey(const ValueKey('bulk-plus-DOM-02')));
      await tester.pump();
      expect(_text(tester, 'bulk-qty-DOM-02'), '100');

      // Pipes: Mukhil Mini qty 10, then +1.
      // Phones: the tab row scrolls sideways.
      await tester.ensureVisible(
        find.byKey(const ValueKey('bulk-category-pipes')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('bulk-category-pipes')));
      await tester.pumpAndSettle();
      expect(_text(tester, 'bulk-min-MUK-05'), 'Minimum Order Qty 10 NOS');
      expect(_text(tester, 'bulk-qty-MUK-05'), '10');
      await tester.tap(find.byKey(const ValueKey('bulk-plus-MUK-05')));
      await tester.pump();
      expect(_text(tester, 'bulk-qty-MUK-05'), '11');
      await tester.tap(find.byKey(const ValueKey('bulk-minus-MUK-05')));
      await tester.tap(find.byKey(const ValueKey('bulk-minus-MUK-05')));
      await tester.pump();
      expect(_text(tester, 'bulk-qty-MUK-05'), '10');
      // Empty Bulk category.
      // Phones: the tab row scrolls sideways.
      await tester.ensureVisible(
        find.byKey(const ValueKey('bulk-category-spares')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('bulk-category-spares')));
      await tester.pumpAndSettle();
      expect(
        find.text('No bulk offers in Spare Parts & Valves yet.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });
  }

  testWidgets('normal listing card never shows the bulk price', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 380,
            height: ListingProductCard.tileExtent(380),
            child: ListingProductCard(
              product: _cruze,
              onTap: () {},
              onAddToCart: (_) async => true,
            ),
          ),
        ),
      ),
    );
    expect(find.text('₹80'), findsOneWidget);
    expect(find.text('₹590'), findsOneWidget);
    expect(find.textContaining('77'), findsNothing);
    expect(find.textContaining('42 PCS'), findsNothing);
  });

  _detailsTests();
}

const _dummy = ProductModel(
  id: 'X',
  name: 'X',
  sku: 'X',
  categoryId: 'filters',
  categoryName: 'filters',
  brand: '',
  mrp: 20,
  dealerPrice: 10,
  imageUrl: '',
  stockStatus: StockStatus.inStock,
  moq: 1,
);

String _loc() => _router.routerDelegate.currentConfiguration.uri.toString();

void _detailsTests() {
  for (final width in [1400.0, 390.0]) {
    testWidgets('card opens Bulk Product Details; controls do not ($width)', (
      tester,
    ) async {
      final cart = await _pump_(tester, width);
      // Images are the focus: a large image box on each card.
      final card = tester.getSize(
        find.byKey(const ValueKey('bulk-open-DOM-01')),
      );
      expect(card.height, greaterThan(300));
      // Plus / Add to Cart work and stay on the list.
      await tester.ensureVisible(
        find.byKey(const ValueKey('bulk-plus-DOM-01')),
      );
      await tester.tap(find.byKey(const ValueKey('bulk-plus-DOM-01')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('bulk-add-DOM-01')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(cart.added.single, ('DOM-01', 84, PurchaseMode.bulk));
      expect(find.byType(BulkProductDetailsScreen), findsNothing);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      // Tap the product: details with bulk pricing only.
      await tester.ensureVisible(
        find.byKey(const ValueKey('bulk-name-DOM-01')),
      );
      await tester.tap(find.byKey(const ValueKey('bulk-name-DOM-01')));
      await tester.pumpAndSettle();
      expect(_loc(), '/bulk-orders/product/DOM-01?category=filters');
      expect(find.byType(BulkProductDetailsScreen), findsOneWidget);
      expect(find.text('Cruze gold inline'), findsOneWidget);
      expect(_text(tester, 'bulk-price-DOM-01'), '₹77 / piece');
      expect(_text(tester, 'bulk-min-DOM-01'), 'Minimum Pack 42 PCS');
      expect(
        _text(tester, 'bulk-min-value-DOM-01'),
        'Minimum Order Value ₹3,234',
      );
      expect(_text(tester, 'bulk-step-DOM-01'), 'Increment +42 (1 pack)');
      expect(find.text('₹80'), findsNothing, reason: 'no Unit/Dealer Price');
      expect(find.textContaining('590'), findsNothing, reason: 'no MRP');
      expect(find.textContaining('% OFF'), findsNothing);
      // Quantity rules on the details page.
      expect(_text(tester, 'bulk-qty-DOM-01'), '42');
      await tester.tap(find.byKey(const ValueKey('bulk-minus-DOM-01')));
      await tester.pump();
      expect(_text(tester, 'bulk-qty-DOM-01'), '42');
      await tester.tap(find.byKey(const ValueKey('bulk-plus-DOM-01')));
      await tester.pump();
      expect(_text(tester, 'bulk-qty-DOM-01'), '84');
      expect(_text(tester, 'bulk-total-DOM-01'), '₹6,468');
      await tester.ensureVisible(find.byKey(const ValueKey('bulk-add-DOM-01')));
      await tester.tap(find.byKey(const ValueKey('bulk-add-DOM-01')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(cart.added.last, ('DOM-01', 84, PurchaseMode.bulk));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      // Back to Bulk Orders, same category.
      await tester.ensureVisible(
        find.byKey(const ValueKey('bulk-details-back')),
      );
      await tester.tap(find.byKey(const ValueKey('bulk-details-back')));
      await tester.pumpAndSettle();
      expect(_loc(), '/bulk-orders?category=filters');
      expect(
        find.text('2 Bulk Products in Filters & Cartridges'),
        findsOneWidget,
      );
    });
  }

  testWidgets('direct link / refresh keeps bulk context', (tester) async {
    await _pump_(
      tester,
      1400,
      location: '/bulk-orders/product/MUK-05?category=pipes',
    );
    expect(find.text('Ro pipe 3/8 100mtr white'), findsOneWidget);
    expect(_text(tester, 'bulk-price-MUK-05'), '₹980 / piece');
    expect(_text(tester, 'bulk-min-MUK-05'), 'Minimum Order Qty 10 NOS');
    expect(find.textContaining('2,800'), findsNothing, reason: 'no MRP');
    await tester.tap(find.byKey(const ValueKey('bulk-plus-MUK-05')));
    await tester.pump();
    expect(_text(tester, 'bulk-qty-MUK-05'), '11');
    await tester.tap(find.byKey(const ValueKey('bulk-details-back')));
    await tester.pumpAndSettle();
    expect(find.text('1 Bulk Products in Pipes & Tubing'), findsOneWidget);
    // Without ?category=, Back uses the product's own category.
    _router.go('/bulk-orders/product/DOM-02');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bulk-details-back')));
    await tester.pumpAndSettle();
    expect(_loc(), '/bulk-orders?category=filters');
    // Not a bulk product: a clear message, no prices.
    _router.go('/bulk-orders/product/F-1');
    await tester.pumpAndSettle();
    expect(
      find.text('Plain Filter is not available in Bulk Orders.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('tabs keep the category in the address', (tester) async {
    await _pump_(tester, 1400);
    await tester.tap(find.byKey(const ValueKey('bulk-category-pipes')));
    await tester.pumpAndSettle();
    expect(_loc(), '/bulk-orders?category=pipes');
    expect(find.text('1 Bulk Products in Pipes & Tubing'), findsOneWidget);
  });

  testWidgets('cart Checkout: a bulk line above the normal maximum is fine '
      '(Mukhil: normal max 40, bulk 41)', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 1400);
    addTearDown(tester.view.reset);
    // Mukhil membrane: normal purchase at most 40 (PDF Mini qty); bulk from
    // 40, then +1.
    const membrane = ProductModel(
      id: 'MUK-23',
      name: '300 GPD Membrane',
      sku: 'MUK-23',
      categoryId: 'membranes',
      categoryName: 'Membranes',
      brand: '',
      mrp: 2800,
      dealerPrice: 1250,
      bulkPrice: 1190,
      bulkMinQty: 40,
      bulkStep: 1,
      bulkPackLabel: '40 NOS',
      maxOrderQuantity: 40,
      imageUrl: '',
      stockStatus: StockStatus.inStock,
      moq: 1,
    );
    expect(membrane.exceedsMaximum(41), isTrue, reason: 'normal rule');
    expect(membrane.bulkQuantityProblem(41), isNull, reason: 'bulk rule');
    expect(membrane.bulkQuantityProblem(39), isNotNull);
    final cart = _FixedCart([
      const CartItemModel(
        product: membrane,
        quantity: 41,
        mode: PurchaseMode.bulk,
      ),
    ]);
    final router = GoRouter(
      initialLocation: '/cart',
      routes: [
        GoRoute(path: '/cart', builder: (_, __) => const CartScreen()),
        GoRoute(
          path: '/checkout',
          builder: (_, __) => const Text('CHECKOUT PAGE'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogProductsProvider.overrideWith((ref) async => [membrane]),
          catalogCategoriesProvider.overrideWith((ref) async => _categories),
          cartProvider.overrideWith((ref) => cart),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Checkout'));
    await tester.pumpAndSettle();
    expect(find.text('Maximum Order Quantity Reached'), findsNothing);
    expect(find.text('CHECKOUT PAGE'), findsOneWidget);
  });
}

class _FixedCart extends CartNotifier {
  _FixedCart(this.lines) : super(ApiClient(), 'test-user', catalog: () => []);
  final List<CartItemModel> lines;
  @override
  Future<void> refreshCart() async {
    state = CartState(items: lines);
  }
}
