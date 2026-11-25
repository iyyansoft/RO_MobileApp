import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/home/domain/home_best_sellers.dart';
import 'package:ro_wholesale_dealer_app/features/home/presentation/widgets/home_product_card.dart';
import 'package:ro_wholesale_dealer_app/features/home/presentation/widgets/home_product_carousel.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/cabinet_display_order.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/category_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/providers/product_provider.dart';

ProductModel p(String sku, String category, double price, double mrp) =>
    ProductModel.fromJson({
      'id': 'id-$sku',
      'sku': sku,
      'name': 'Product $sku',
      'category': category,
      'price': price,
      'mrp': mrp,
      'img': '',
    });

// Catalogue order (category, then name), with the user's local prices.
final catalog = [
  p('CAB-39', 'cabinets', 280, 0),
  p('CAB-41', 'cabinets', 430, 1290),
  p('CAB-40', 'cabinets', 360, 1080),
  p('CAB-38', 'cabinets', 950, 3000),
  p('CAB-37', 'cabinets', 850, 2800),
  p('CAB-36', 'cabinets', 750, 2800),
  for (var i = 1; i <= 35; i++)
    p(
      'CAB-${i.toString().padLeft(2, '0')}',
      'cabinets',
      4000,
      i.isEven ? 12000 : 0,
    ),
  p('MUK-21', 'filters', 100, 520),
  p('DOM-02', 'filters', 50, 500),
  p('RO-SYS-25', 'systems', 16500, 22000),
  p('MUK-24', 'systems', 6200, 12500),
  p('RO-SYS-10L', 'systems', 7500, 10000),
];

List<String> skus(Iterable<ProductModel> l) => [for (final x in l) x.sku];

const categories = [
  CategoryModel(
    id: 'filters',
    name: 'Filters',
    imagePath: '',
    productCount: 0,
    description: '',
  ),
  CategoryModel(
    id: 'cabinets',
    name: 'Cabinet',
    imagePath: '',
    productCount: 0,
    description: '',
    databaseId: 'CAT_CAB',
  ),
  CategoryModel(
    id: 'systems',
    name: 'RO Systems',
    imagePath: '',
    productCount: 0,
    description: '',
    databaseId: 'CAT_SYS',
  ),
];

/// Slider input for the widget tests (41 Cabinet products).
final slider = [
  for (final x in catalog)
    if (x.categoryId == 'cabinets') x,
];

void main() {
  List<ProductModel> categoryPage(ProviderContainer c, String id) {
    c.read(productFilterProvider.notifier).selectCategory(id);
    return c.read(filteredProductsProvider);
  }

  ProviderContainer container(
    List<ProductModel> products, {
    List<CategoryModel> cats = categories,
  }) {
    final c = ProviderContainer(
      overrides: [
        allProductsProvider.overrideWithValue(products),
        categoriesProvider.overrideWithValue(cats),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('Best Sellers = the complete RO Systems page list, same SKU sequence', () {
    final c = container(catalog);
    final home = skus(c.read(roSystemsBestSellersProvider));
    final page = skus(categoryPage(c, 'systems'));
    expect(home, page, reason: 'identical count and order');
    expect(home.length, 3 + 41, reason: 'own products + cross-listed Cabinets');
    expect(home.toSet().length, home.length, reason: 'no duplicates');
    expect(home, containsAll(['RO-SYS-25', 'MUK-24', 'RO-SYS-10L', 'CAB-15']));
  });

  test('View All opens with the default sort, so it matches the slider', () {
    List<String> page(SortOption sort) {
      final c = ProviderContainer(
        overrides: [
          allProductsProvider.overrideWithValue(catalog),
          categoriesProvider.overrideWithValue(categories),
          productFilterProvider.overrideWith(
            (ref) => ProductNotifier(
              initialState: ProductFilterState(
                selectedCategoryId: 'systems',
                sortOption: sort,
              ),
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      return skus(c.read(filteredProductsProvider));
    }

    final slider = skus(container(catalog).read(roSystemsBestSellersProvider));
    // ProductListingScreen(initialSortOption: const ProductFilterState().sortOption)
    expect(page(const ProductFilterState().sortOption), slider);
    // Without it, a dealer's saved "Price: High to Low" would reorder View All.
    expect(page(SortOption.priceHighToLow), isNot(slider));
  });

  test('ties keep the catalogue order (stable sort, >32 products: web = Android)', () {
    final c = container(catalog);
    final expected = skus(cabinetDisplayOrder([
      for (final x in catalog)
        if (x.categoryId == 'systems' || x.categoryId == 'cabinets') x,
    ]));
    expect(expected.length, greaterThan(32));
    expect(skus(c.read(roSystemsBestSellersProvider)), expected);
    expect(skus(categoryPage(c, 'systems')), expected);
  });

  test('refresh / reload: the same catalogue always gives the same sequence', () {
    final first = skus(container(catalog).read(roSystemsBestSellersProvider));
    final again = skus(container([...catalog]).read(roSystemsBestSellersProvider));
    expect(again, first);
  });

  test('admin add / edit / remove shows up from the latest catalogue', () {
    final edited = [
      for (final x in catalog)
        if (x.sku != 'MUK-24') // removed
          x.sku == 'RO-SYS-25' ? p('RO-SYS-25', 'systems', 999, 2000) : x, // edited
      p('RO-SYS-99', 'systems', 500, 900), // added
      p('CAB-99', 'cabinets', 500, 900), // new Cabinet: cross-listed, so shown
      p('MEM-99', 'membranes', 500, 900), // other categories never appear
    ];
    final c = container(edited);
    final home = c.read(roSystemsBestSellersProvider);
    expect(skus(home), isNot(contains('MUK-24')));
    expect(skus(home), containsAll(['RO-SYS-99', 'CAB-99']));
    expect(skus(home), isNot(contains('MEM-99')));
    expect(home.firstWhere((x) => x.sku == 'RO-SYS-25').dealerPrice, 999);
    expect(skus(home), skus(categoryPage(c, 'systems')));
  });

  test('no RO Systems category: empty, Home falls back to the previous rule', () {
    final others = [
      p('MUK-21', 'filters', 100, 520),
      p('A', 'filters', 90, 100),
    ];
    final c = container(others, cats: [categories.first]);
    expect(c.read(roSystemsBestSellersProvider), isEmpty);
    expect(skus(homeBestSellersFallback(others)), ['MUK-21']);
    expect(skus(homeBestSellersFallback([p('A', 'filters', 90, 100)])), ['A']);
  });

  Future<void> pumpCarousel(
    WidgetTester tester,
    double width,
    int visible, {
    bool autoScroll = false,
  }) async {
    tester.view.physicalSize = Size(width, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HomeProductCarousel(
              products: slider,
              visibleCount: visible,
              sectionKey: 'best_sellers',
              spacing: 20,
              autoScroll: autoScroll,
              onTap: (_, __) {},
              onAddToCart: (_) {},
            ),
          ),
        ),
      ),
    );
    if (autoScroll) {
      await tester.pump();
      await tester.pump();
    } else {
      await tester.pumpAndSettle();
    }
  }

  /// SKUs of the cards fully on screen, left to right (any copy of the loop).
  List<String> visibleSkus(WidgetTester tester, double width) {
    final shown = <(double, String)>[];
    for (final e in find.byType(HomeProductCard).evaluate()) {
      final key = (e.widget.key! as ValueKey<String>).value;
      final sku = RegExp(r'card-id-(CAB-\d+)').firstMatch(key)!.group(1)!;
      final box = e.renderObject! as RenderBox;
      final left = box.localToGlobal(Offset.zero).dx;
      if (left >= -0.5 && left + box.size.width <= width + 0.5) {
        shown.add((left, sku));
      }
    }
    shown.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final s in shown) s.$2];
  }

  double leftOf(WidgetTester tester, String sku) => tester
      .getRect(find.byKey(ValueKey('home-best_sellers-card-id-$sku')))
      .left;

  final prev = find.byKey(const ValueKey('home-carousel-best_sellers-prev'));
  final next = find.byKey(const ValueKey('home-carousel-best_sellers-next'));

  testWidgets('desktop: 4 cards visible; arrows loop endlessly both ways', (
    tester,
  ) async {
    const w = 1300.0;
    await pumpCarousel(tester, w, 4);
    expect(visibleSkus(tester, w), ['CAB-39', 'CAB-41', 'CAB-40', 'CAB-38']);
    expect(prev, findsOneWidget, reason: 'endless: back works from the start');
    expect(next, findsOneWidget);

    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(visibleSkus(tester, w), ['CAB-37', 'CAB-36', 'CAB-01', 'CAB-02']);
    await tester.tap(prev);
    await tester.pumpAndSettle();
    expect(visibleSkus(tester, w), ['CAB-39', 'CAB-41', 'CAB-40', 'CAB-38']);
    // Before the first product come the last ones (seamless loop).
    await tester.tap(prev);
    await tester.pumpAndSettle();
    expect(visibleSkus(tester, w), ['CAB-32', 'CAB-33', 'CAB-34', 'CAB-35']);

    // Forward through everything: all 41 seen, then it continues from the start.
    await tester.tap(next);
    await tester.pumpAndSettle();
    final seen = <String>{};
    for (var i = 0; i < 11; i++) {
      seen.addAll(visibleSkus(tester, w));
      await tester.tap(next);
      await tester.pumpAndSettle();
    }
    expect(seen.length, 41, reason: 'every product reachable');
    expect(visibleSkus(tester, w), [
      'CAB-38',
      'CAB-37',
      'CAB-36',
      'CAB-01',
    ], reason: 'after the last product the first ones follow');
    expect(tester.takeException(), isNull);
  });

  testWidgets('auto-scroll: slow, smooth, continuous, not paused by hover', (
    tester,
  ) async {
    const w = 1300.0;
    await pumpCarousel(tester, w, 4, autoScroll: true);
    final start = leftOf(tester, 'CAB-41');
    // 5 s at 60 fps: about 28 px/s, at most ~1.4 px per frame (no jumps).
    var last = start;
    var maxStep = 0.0;
    for (var i = 0; i < 300; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final now = leftOf(tester, 'CAB-41');
      maxStep = maxStep > last - now ? maxStep : last - now;
      expect(now, lessThanOrEqualTo(last), reason: 'only right to left');
      last = now;
    }
    final moved = start - last;
    expect(moved, closeTo(28 * 300 * 0.016, 12));
    expect(maxStep, lessThan(1.5));

    // Hovering does not stop it.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(ListView)));
    final before = leftOf(tester, 'CAB-41');
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(leftOf(tester, 'CAB-41'), lessThan(before - 20));

    // Removing the carousel disposes its single ticker cleanly.
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('auto-scroll is off in tests by default (no endless frames)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1300, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HomeProductCarousel(
              products: slider,
              visibleCount: 4,
              sectionKey: 'best_sellers',
              onTap: (_, __) {},
              onAddToCart: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(); // would time out if it kept scrolling
    expect(visibleSkus(tester, 1300), ['CAB-39', 'CAB-41', 'CAB-40', 'CAB-38']);
  });

  testWidgets('drag/swipe scrolls sideways', (tester) async {
    const w = 400.0;
    await pumpCarousel(tester, w, 2);
    final list = find.byKey(const ValueKey('home-carousel-best_sellers'));
    expect(visibleSkus(tester, w).first, 'CAB-39');
    await tester.drag(list, const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(visibleSkus(tester, w), isNot(contains('CAB-39')));
  });
}
