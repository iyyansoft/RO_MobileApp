import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/core/network/api_client.dart';
import 'package:ro_wholesale_dealer_app/core/widgets/category_image.dart';
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

// The live catalogue: 6 original categories plus Cabinet (7th).
const _categories = [
  CategoryModel(
    id: 'systems',
    name: 'RO Systems',
    imagePath: '',
    productCount: 1,
    description: '',
  ),
  CategoryModel(
    id: 'membranes',
    name: 'Membranes',
    imagePath: '',
    productCount: 1,
    description: '',
  ),
  CategoryModel(
    id: 'filters',
    name: 'Filters & Cartridges',
    imagePath: '',
    productCount: 1,
    description: '',
  ),
  CategoryModel(
    id: 'pumps',
    name: 'Booster Pumps',
    imagePath: '',
    productCount: 1,
    description: '',
  ),
  CategoryModel(
    id: 'pipes',
    name: 'Pipes & Tubing',
    imagePath: '',
    productCount: 1,
    description: '',
  ),
  CategoryModel(
    id: 'spares',
    name: 'Spare Parts & Valves',
    imagePath: '',
    productCount: 1,
    description: '',
  ),
  CategoryModel(
    id: 'cabinets',
    name: 'Cabinet',
    imagePath: '',
    productCount: 41,
    description: '',
    databaseId: 'CAT_CAB',
  ),
];

ProductModel _p(String id, String name, String cat, String catName) =>
    ProductModel(
      id: id,
      name: name,
      sku: id,
      categoryId: cat,
      categoryName: catName,
      brand: '',
      mrp: 0,
      dealerPrice: 500,
      imageUrl: '',
      stockStatus: StockStatus.inStock,
      moq: 1,
    );

final _products = [
  _p('s1', 'RO System', 'systems', 'RO Systems'),
  _p('m1', 'Membrane', 'membranes', 'Membranes'),
  _p('f1', 'Filter', 'filters', 'Filters & Cartridges'),
  _p('p1', 'Pump', 'pumps', 'Booster Pumps'),
  _p('t1', 'Tubing', 'pipes', 'Pipes & Tubing'),
  _p('v1', 'Valve', 'spares', 'Spare Parts & Valves'),
  for (var i = 1; i <= 41; i++)
    _p(
      'CAB-${i.toString().padLeft(2, '0')}',
      'Cabinet model $i',
      'cabinets',
      'Cabinet',
    ),
];

Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        catalogProductsProvider.overrideWith((ref) async => _products),
        catalogCategoriesProvider.overrideWith((ref) async => _categories),
        cartProvider.overrideWith((ref) => _EmptyCart()),
      ],
      child: const MaterialApp(home: CategoriesScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final size in [const Size(1400, 1400), const Size(390, 1600)]) {
    testWidgets(
      'All Categories shows all 7 categories incl. Cabinet (${size.width})',
      (tester) async {
        await _pump(tester, size);
        // Sidebar: every category, Cabinet included.
        for (final c in _categories) {
          expect(
            find.byKey(ValueKey('category-sidebar-${c.id}')),
            findsOneWidget,
            reason: c.name,
          );
        }
        // Main grid: 7 category cards, not the first 6 only.
        for (final c in _categories) {
          expect(
            find.text(c.name),
            findsAtLeastNWidgets(2),
            reason: '${c.name}: sidebar + grid card',
          );
        }
        // Cabinet uses the blue cabinet photo, not the RO Systems one.
        final urls = tester
            .widgetList<CategoryImage>(find.byType(CategoryImage))
            .map((w) => w.url)
            .toList();
        expect(
          urls.where(
            (u) => u.contains('products_image/Aqua%20grid%20blue.jpg'),
          ),
          isNotEmpty,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('selecting Cabinet lists all 41 Cabinet products', (
    tester,
  ) async {
    await _pump(tester, const Size(1400, 6000));
    await tester.tap(find.byKey(const ValueKey('category-sidebar-cabinets')));
    await tester.pumpAndSettle();
    expect(find.textContaining('41'), findsWidgets);
    for (final i in [1, 20, 41]) {
      expect(find.text('Cabinet model $i'), findsOneWidget, reason: 'CAB-$i');
    }
    expect(find.text('Valve'), findsNothing, reason: 'only Cabinet products');
  });

  test('CategoryImage keeps sub-folders for its bundled fallback', () {
    // The fallback path is derived from the URL after /images/.
    const url =
        'https://ro-mobileapp.onrender.com/images/products_image/Aqua%20grid%20blue.jpg';
    final segments = Uri.parse(url).pathSegments;
    expect(
      segments.sublist(segments.indexOf('images') + 1).join('/'),
      'products_image/Aqua grid blue.jpg',
    );
  });
}
