import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ro_wholesale_dealer_app/features/cart/domain/models/cart_item_model.dart';
import 'package:ro_wholesale_dealer_app/core/network/api_client.dart';
import 'package:ro_wholesale_dealer_app/features/cart/presentation/providers/cart_provider.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/category_price_view.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/category_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/providers/product_provider.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/screens/categories_screen.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/screens/product_details_screen.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/screens/product_listing_screen.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/widgets/listing_product_card.dart';

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

// Same identities as the live catalogue (key, CAT_ id, title).
const _systems = CategoryModel(
  id: 'systems',
  databaseId: 'CAT_SYS',
  name: 'RO Systems',
  imagePath: '',
  productCount: 0,
  description: '',
);
const _membranes = CategoryModel(
  id: 'membranes',
  databaseId: 'CAT_MEM',
  name: 'Membranes',
  imagePath: '',
  productCount: 0,
  description: '',
);
const _cabinets = CategoryModel(
  id: 'cabinets',
  databaseId: 'CAT_CAB',
  name: 'Cabinet',
  imagePath: '',
  productCount: 0,
  description: '',
);
const _categories = [_systems, _membranes, _cabinets];

ProductModel _p(
  String id,
  CategoryModel cat,
  double price,
  double mrp, {
  double? cabinet,
}) => ProductModel(
  id: id,
  name: 'Product $id',
  sku: id,
  categoryId: cat.id,
  categoryName: cat.name,
  brand: '',
  mrp: mrp,
  dealerPrice: price,
  cabinetPrice: cabinet,
  imageUrl: '',
  stockStatus: StockStatus.inStock,
  moq: 1,
);

final _products = [
  _p('SYS-1', _systems, 16500, 22000),
  _p('MEM-1', _membranes, 650, 900),
  _p('CAB-15', _cabinets, 4650, 13500, cabinet: 1850),
  _p('CAB-18', _cabinets, 5300, 13800, cabinet: 2500),
  _p('CAB-40', _cabinets, 360, 1080, cabinet: 375),
];

Future<_RecordingCart> _pumpListing(
  WidgetTester tester,
  String categoryId, {
  double width = 1400,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 2400);
  addTearDown(tester.view.reset);
  final cart = _RecordingCart();
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => ProductListingScreen(initialCategoryId: categoryId),
      ),
      GoRoute(path: '/cart', builder: (_, __) => const Text('CART')),
      GoRoute(path: '/categories', builder: (_, __) => const Text('CATS')),
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

String _price(WidgetTester tester, String id) =>
    tester.widget<Text>(find.byKey(ValueKey('listing-price-$id'))).data!;

void main() {
  group('membership', () {
    List<String> ids(String category) => listingProducts(
      _products,
      _categories,
      ProductFilterState(selectedCategoryId: category),
    ).map((p) => p.id).toList();

    test('RO Systems = its own products + every Cabinet product', () {
      expect(
        ids('systems'),
        unorderedEquals(['SYS-1', 'CAB-15', 'CAB-18', 'CAB-40']),
      );
      expect(ids('CAT_SYS'), hasLength(4), reason: 'by database id too');
      expect(ids('cabinets'), unorderedEquals(['CAB-15', 'CAB-18', 'CAB-40']));
      expect(ids('membranes'), ['MEM-1'], reason: 'others unchanged');
      // The very same records, not copies.
      final ro = listingProducts(
        _products,
        _categories,
        const ProductFilterState(selectedCategoryId: 'systems'),
      );
      expect(
        identical(ro.firstWhere((p) => p.id == 'CAB-15'), _products[2]),
        isTrue,
      );
      // All products: each product once.
      final all = listingProducts(
        _products,
        _categories,
        const ProductFilterState(),
      );
      expect(all.length, _products.length);
    });

    test('Cabinet page sorts and filters by the Cabinet Price it shows', () {
      final asc = listingProducts(
        _products,
        _categories,
        const ProductFilterState(
          selectedCategoryId: 'cabinets',
          sortOption: SortOption.priceLowToHigh,
        ),
      ).map((p) => p.id);
      expect(asc, ['CAB-40', 'CAB-15', 'CAB-18']); // 375, 1850, 2500
      final ro = listingProducts(
        _products,
        _categories,
        const ProductFilterState(
          selectedCategoryId: 'systems',
          sortOption: SortOption.priceLowToHigh,
        ),
      ).map((p) => p.id);
      expect(ro, ['CAB-40', 'CAB-15', 'CAB-18', 'SYS-1']); // dealer prices
    });

    test('view per category; RO Systems recognised by key, id or name', () {
      expect(priceViewFor(_cabinets), ProductPriceView.cabinet);
      expect(priceViewFor(_systems), ProductPriceView.roSystems);
      expect(priceViewFor(_membranes), ProductPriceView.standard);
      expect(priceViewFor(null), ProductPriceView.standard);
      expect(ProductPriceView.fromQuery('cabinet'), ProductPriceView.cabinet);
      expect(
        ProductPriceView.fromQuery('ro-systems'),
        ProductPriceView.roSystems,
      );
      expect(ProductPriceView.fromQuery(null), ProductPriceView.standard);
    });
  });

  testWidgets('category counts include the Cabinet products in RO Systems', (
    tester,
  ) async {
    late List<CategoryModel> counted;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogProductsProvider.overrideWith((ref) async => _products),
          catalogCategoriesProvider.overrideWith((ref) async => _categories),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            counted = ref.watch(categoriesProvider);
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      {for (final c in counted) c.id: c.productCount},
      {'systems': 4, 'membranes': 1, 'cabinets': 3},
    );
  });

  for (final width in [1400.0, 390.0]) {
    testWidgets('Cabinets page: Cabinet Price only ($width)', (tester) async {
      await _pumpListing(tester, 'cabinets', width: width);
      expect(find.text('3 Products Found'), findsOneWidget);
      expect(_price(tester, 'CAB-15'), '₹1,850');
      expect(find.text('Cabinet Price'), findsNWidgets(3));
      expect(find.text('₹4,650'), findsNothing, reason: 'no Dealer Price');
      expect(find.text('₹13,500'), findsNothing, reason: 'no MRP');
      expect(find.textContaining('% OFF'), findsNothing);
      expect(find.textContaining('Cabinet Price:'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'RO Systems page: Dealer Price + MRP, never Cabinet Price ($width)',
      (tester) async {
        final cart = await _pumpListing(tester, 'systems', width: width);
        expect(find.text('4 Products Found'), findsOneWidget);
        expect(_price(tester, 'CAB-15'), '₹4,650');
        expect(find.text('₹13,500'), findsOneWidget);
        expect(find.text('66% OFF'), findsOneWidget);
        expect(_price(tester, 'SYS-1'), '₹16,500');
        expect(find.textContaining('Cabinet Price'), findsNothing);
        expect(tester.takeException(), isNull);
        // Add to Cart adds the same product record (same id).
        final card = find.byKey(const ValueKey('listing-card-CAB-15'));
        await tester.ensureVisible(card);
        await tester.tap(
          find.descendant(of: card, matching: find.text('Add to Cart')),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(cart.added.single.$1, 'CAB-15');
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets('Membranes page keeps the existing display', (tester) async {
    await _pumpListing(tester, 'membranes');
    expect(_price(tester, 'MEM-1'), '₹650');
    expect(find.text('₹900'), findsOneWidget);
  });

  testWidgets('details opened from each page follow its price format', (
    tester,
  ) async {
    await _pumpListing(tester, 'cabinets');
    await tester.tap(find.text('Product CAB-15').first);
    await tester.pumpAndSettle();
    expect(find.byType(ProductDetailsScreen), findsOneWidget);
    expect(
      tester
          .widget<ProductDetailsScreen>(find.byType(ProductDetailsScreen))
          .priceView,
      ProductPriceView.cabinet,
    );
    expect(find.byKey(const ValueKey('details-cabinet-price')), findsOneWidget);
    expect(find.text('₹1,850'), findsOneWidget);
    expect(find.byKey(const ValueKey('details-dealer-price')), findsNothing);
    expect(find.byKey(const ValueKey('details-mrp')), findsNothing);
    expect(find.textContaining('OFF WHOLESALE'), findsNothing);
    expect(find.textContaining('Total:'), findsNothing);

    await _pumpListing(tester, 'systems');
    await tester.tap(find.text('Product CAB-15').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('details-dealer-price')), findsOneWidget);
    expect(find.text('₹4,650'), findsOneWidget);
    expect(find.text('MRP ₹13,500'), findsOneWidget);
    expect(find.textContaining('Cabinet Price'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('details without a category: existing default display', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogProductsProvider.overrideWith((ref) async => _products),
          catalogCategoriesProvider.overrideWith((ref) async => _categories),
          cartProvider.overrideWith((ref) => _RecordingCart()),
        ],
        child: MaterialApp(home: ProductDetailsScreen(product: _products[2])),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('details-dealer-price')), findsOneWidget);
    expect(find.text('MRP ₹13,500'), findsOneWidget);
    expect(find.text('Cabinet Price: ₹1,850'), findsOneWidget);
  });

  testWidgets('All Categories page: same rules per category', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 3000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogProductsProvider.overrideWith((ref) async => _products),
          catalogCategoriesProvider.overrideWith((ref) async => _categories),
          cartProvider.overrideWith((ref) => _RecordingCart()),
        ],
        child: const MaterialApp(home: CategoriesScreen()),
      ),
    );
    await tester.pumpAndSettle();
    String price(String id) =>
        tester.widget<Text>(find.byKey(ValueKey('category-price-$id'))).data!;

    await tester.tap(find.byKey(const ValueKey('category-sidebar-systems')));
    await tester.pumpAndSettle();
    expect(find.textContaining('4 Wholesale Items'), findsOneWidget);
    expect(price('CAB-15'), '₹4,650');
    expect(price('SYS-1'), '₹16,500');
    expect(find.textContaining('Cabinet Price'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('category-sidebar-cabinets')));
    await tester.pumpAndSettle();
    expect(find.textContaining('3 Wholesale Items'), findsOneWidget);
    expect(price('CAB-15'), 'Cabinet Price: ₹1,850');
    expect(find.text('₹4,650'), findsNothing);
    expect(find.text('₹13,500'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
