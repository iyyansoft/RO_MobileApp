import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/category_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/providers/product_provider.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/widgets/catalog_auto_refresh.dart';

/// Rows shaped exactly like GET /api/products.
Map<String, dynamic> _row(String id, String name, String category, String created, {String sku = ''}) => {
  'id': id,
  'category': category,
  'category_id': null,
  'created_at': created,
  'brand': 'RO Wholesale',
  'name': name,
  'price': 900,
  'dealer_price': 900,
  'mrp': 1200,
  'moq': 'MOQ: 1 Unit',
  'badge': '',
  'rating': '★★★★★ (5.0)',
  'img': 'purifier.jpg',
  'sku': sku.isEmpty ? id.toUpperCase() : sku,
  'desc': '',
  'specs': {},
  'features': [],
  'stock_quantity': 50,
  'status': 'active',
};

const _categories = [
  CategoryModel(id: 'membranes', name: 'Membranes', imagePath: '', productCount: 0, description: ''),
  CategoryModel(id: 'pumps', name: 'Booster Pumps', imagePath: '', productCount: 0, description: ''),
];

void main() {
  test('created_at is parsed and newestFirst puts just-added products first', () {
    final products = [
      _row('a', 'Old Membrane', 'membranes', '2026-10-09T08:16:36.000Z'),
      _row('b', 'Undated', 'pumps', ''),
      _row('c', 'New Pump', 'pumps', '2026-11-11T05:33:24.649Z'),
    ].map(ProductModel.fromJson).toList();
    expect(products[2].createdAt, DateTime.utc(2026, 11, 11, 5, 33, 24, 649));
    expect(products[1].createdAt, isNull);
    expect(ProductModel.newestFirst(products).map((p) => p.name), ['New Pump', 'Old Membrane', 'Undated']);
  });

  testWidgets('a product added by the admin appears without a reload', (tester) async {
    // Stands in for the shared backend/database.
    final backend = [_row('a', 'RO Membrane 75 GPD', 'membranes', '2026-10-09T08:16:36.000Z')];
    var productLoads = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogProductsLoaderProvider.overrideWithValue(() async {
            productLoads++;
            return backend.map(ProductModel.fromJson).toList();
          }),
          catalogCategoriesLoaderProvider.overrideWithValue(() async => _categories),
        ],
        child: MaterialApp(
          home: CatalogAutoRefresh(
            interval: const Duration(seconds: 5),
            child: Consumer(
              builder: (context, ref, _) {
                final catalog = ref.watch(catalogProductsProvider);
                if (catalog.isLoading && !catalog.hasValue) return const Text('loading');
                ref.watch(productFilterProvider);
                final pumps = ref
                    .watch(filteredProductsProvider)
                    .where(_categories[1].matchesProduct)
                    .map((p) => p.name);
                return ListView(
                  children: [
                    for (final p in ref.watch(allProductsProvider)) Text('all:${p.name}'),
                    for (final name in pumps) Text('pumps:$name'),
                    Text('count:${ref.watch(categoriesProvider).where((c) => c.id == 'pumps').map((c) => c.productCount).firstOrNull}'),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('all:RO Membrane 75 GPD'), findsOneWidget);
    expect(find.text('count:0'), findsOneWidget);
    expect(productLoads, 1);

    // Unchanged catalog: a check does not rebuild or re-fetch twice.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(productLoads, 2);

    // Admin adds one product, then a bulk upload of two more.
    backend.add(_row('p1', 'RO Booster Pump 100 GPD', 'pumps', '2026-11-11T05:33:24.000Z'));
    backend.add(_row('p2', 'RO Booster Pump 300 GPD', 'pumps', '2026-11-11T05:33:25.000Z'));
    backend.add(_row('m2', 'RO Membrane 100 GPD', 'membranes', '2026-11-11T05:33:26.000Z'));
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('loading'), findsNothing, reason: 'current data stays on screen');
    await tester.pumpAndSettle();

    expect(find.text('all:RO Booster Pump 100 GPD'), findsOneWidget);
    expect(find.text('all:RO Membrane 100 GPD'), findsOneWidget);
    expect(find.text('pumps:RO Booster Pump 100 GPD'), findsOneWidget);
    expect(find.text('pumps:RO Booster Pump 300 GPD'), findsOneWidget);
    expect(find.text('pumps:RO Membrane 100 GPD'), findsNothing);
    expect(find.text('count:2'), findsOneWidget);
    // The refresh hands its download to the provider: one request per check.
    expect(productLoads, 3);

    // Searching finds the new product.
    final container = ProviderScope.containerOf(tester.element(find.byType(CatalogAutoRefresh)));
    container.read(productFilterProvider.notifier).setSearchQuery('pump 300');
    expect(container.read(filteredProductsProvider).map((p) => p.name), ['RO Booster Pump 300 GPD']);

    // Coming back to the app checks immediately.
    backend.add(_row('p3', 'RO Booster Pump 75 GPD', 'pumps', '2026-11-11T06:00:00.000Z'));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('all:RO Booster Pump 75 GPD'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
