import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/home/domain/home_best_sellers.dart';
import 'package:ro_wholesale_dealer_app/features/home/presentation/widgets/home_product_carousel.dart';
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
];

/// Slider input for the widget tests (41 Cabinet products).
final slider = [
  for (final x in catalog)
    if (x.categoryId == 'cabinets') x,
];

void main() {
  List<ProductModel> cabinetPage(ProviderContainer c) {
    final n = c.read(productFilterProvider.notifier);
    n.selectCategory('cabinets');
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

  test(
    'Best Sellers = the Cabinet category page list, same products and order',
    () {
      final c = container(catalog);
      final home = c.read(cabinetCategoryProductsProvider);
      final page = cabinetPage(c);
      expect(skus(home), skus(page));
      expect(home.length, 41);
      expect(home.map((x) => x.id).toSet().length, 41, reason: 'no duplicates');
      expect(
      skus(home.skip(35)).toSet(),
      {'CAB-36', 'CAB-37', 'CAB-38', 'CAB-39', 'CAB-40', 'CAB-41'}, reason: 'same Cabinet-page rule: the six 20" housings last');
      expect(
        home.every((x) => x.categoryId == 'cabinets'),
        isTrue,
        reason: 'no unrelated products',
      );
      expect(
        identical(home.firstWhere((x) => x.sku == 'CAB-40'), catalog[2]),
        isTrue,
      );
    },
  );

  test('admin add / edit / remove shows up from the latest catalogue', () {
    final edited = [
      for (final x in catalog)
        if (x.sku != 'CAB-02') // removed
          x.sku == 'CAB-01' ? p('CAB-01', 'cabinets', 999, 2000) : x, // edited
      p('CAB-42', 'cabinets', 500, 900), // added
    ];
    final c = container(edited);
    final home = c.read(cabinetCategoryProductsProvider);
    expect(skus(home), skus(cabinetPage(c)));
    expect(skus(home), isNot(contains('CAB-02')));
    expect(skus(home), contains('CAB-42'));
    expect(home.firstWhere((x) => x.sku == 'CAB-01').dealerPrice, 999);
  });

  test('no Cabinet category: empty, Home falls back to the previous rule', () {
    final others = [
      p('MUK-21', 'filters', 100, 520),
      p('A', 'filters', 90, 100),
    ];
    final c = container(others, cats: [categories.first]);
    expect(c.read(cabinetCategoryProductsProvider), isEmpty);
    expect(skus(homeBestSellersFallback(others)), ['MUK-21']);
    expect(skus(homeBestSellersFallback([p('A', 'filters', 90, 100)])), ['A']);
  });

  Future<void> pumpCarousel(
    WidgetTester tester,
    double width,
    int visible,
  ) async {
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
              onTap: (_, __) {},
              onAddToCart: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool fullyVisible(WidgetTester tester, String sku, double width) {
    final f = find.byKey(ValueKey('home-best_sellers-card-id-$sku'));
    if (f.evaluate().isEmpty) return false;
    final r = tester.getRect(f);
    return r.left >= -0.5 && r.right <= width + 0.5;
  }

  testWidgets(
    'desktop: exactly 4 cards visible; arrows move to the rest and back',
    (tester) async {
      const w = 1300.0;
      await pumpCarousel(tester, w, 4);
      final all = skus(slider);
      expect(
        [
          for (final s in all)
            if (fullyVisible(tester, s, w)) s,
        ],
        ['CAB-39', 'CAB-41', 'CAB-40', 'CAB-38'],
      );
      expect(
        find.byKey(const ValueKey('home-carousel-best_sellers-prev')),
        findsNothing,
      );
      final next = find.byKey(
        const ValueKey('home-carousel-best_sellers-next'),
      );
      expect(next, findsOneWidget);

      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(
        [
          for (final s in all)
            if (fullyVisible(tester, s, w)) s,
        ],
        ['CAB-37', 'CAB-36', 'CAB-01', 'CAB-02'],
      );
      expect(
        find.byKey(const ValueKey('home-carousel-best_sellers-prev')),
        findsOneWidget,
      );

      // Every product is reachable: page to the end.
      final reached = <String>{};
      for (var i = 0; i < 20 && next.evaluate().isNotEmpty; i++) {
        reached.addAll([
          for (final s in all)
            if (fullyVisible(tester, s, w)) s,
        ]);
        await tester.tap(next);
        await tester.pumpAndSettle();
      }
      reached.addAll([
        for (final s in all)
          if (fullyVisible(tester, s, w)) s,
      ]);
      expect(reached.length, 37, reason: 'every product after the first page');
      expect(
        {...reached, 'CAB-39', 'CAB-41', 'CAB-40', 'CAB-38'}.length,
        41,
        reason: 'all 41 reachable',
      );
      expect(fullyVisible(tester, all.last, w), isTrue);
      expect(next, findsNothing, reason: 'no next arrow at the end');

      await tester.tap(
        find.byKey(const ValueKey('home-carousel-best_sellers-prev')),
      );
      await tester.pumpAndSettle();
      expect(fullyVisible(tester, all.last, w), isFalse);
    },
  );

  testWidgets('drag/swipe scrolls sideways', (tester) async {
    const w = 400.0;
    await pumpCarousel(tester, w, 2);
    final list = find.byKey(const ValueKey('home-carousel-best_sellers'));
    expect(fullyVisible(tester, 'CAB-39', w), isTrue);
    await tester.drag(list, const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(fullyVisible(tester, 'CAB-39', w), isFalse);
  });
}
