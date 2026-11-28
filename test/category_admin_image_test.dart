import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/core/network/api_client.dart';
import 'package:ro_wholesale_dealer_app/core/widgets/category_image.dart';
import 'package:ro_wholesale_dealer_app/features/cart/presentation/providers/cart_provider.dart';
import 'package:ro_wholesale_dealer_app/features/home/presentation/screens/home_screen.dart';
import 'package:ro_wholesale_dealer_app/features/home/presentation/widgets/home_category_card.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/category_image_source.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/category_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/providers/product_provider.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/screens/categories_screen.dart';

class _EmptyCart extends CartNotifier {
  _EmptyCart() : super(ApiClient(), 'test-user', catalog: () => []);
  @override
  Future<void> refreshCart() async {}
}

final _origin = Uri.parse(ApiClient.defaultBaseUrl).origin;
const _storageUrl =
    'https://example.supabase.co/storage/v1/object/public/ro-product-images/categories/cabinet.jpg';

// As saved in the Admin Panel (Production keeps the old names for most).
const _categories = [
  CategoryModel(id: 'systems', databaseId: 'CAT_SYS', name: 'RO Systems', imagePath: '/images/RO_System_new.png', productCount: 1, description: 'Domestic and commercial RO'),
  CategoryModel(id: 'membranes', databaseId: 'CAT_MEM', name: 'Membranes', imagePath: 'membrane.jpg', productCount: 1, description: ''),
  CategoryModel(id: 'filters', databaseId: 'CAT_FLT', name: 'Filters & Cartridges', imagePath: '/api/product-images/img_1_abc.jpg', productCount: 1, description: ''),
  CategoryModel(id: 'pumps', databaseId: 'CAT_PMP', name: 'Booster Pumps', imagePath: '', productCount: 1, description: ''),
  CategoryModel(id: 'cabinets', databaseId: 'CAT_CAB', name: 'Cabinet', imagePath: _storageUrl, productCount: 1, description: ''),
];

ProductModel _p(String sku, String category, String name) => ProductModel.fromJson({
      'id': 'PDF_$sku', 'sku': sku, 'name': name, 'category_key': category, 'category_name': name,
      'price': 100, 'mrp': 200, 'img': '', 'status': 'active', 'stock_quantity': 5,
    });
final _products = [
  _p('SYS-1', 'systems', 'RO Systems'), _p('MEM-1', 'membranes', 'Membranes'), _p('FLT-1', 'filters', 'Filters & Cartridges'),
  _p('PMP-1', 'pumps', 'Booster Pumps'), _p('CAB-1', 'cabinets', 'Cabinet'),
];

Iterable<String> _shownUrls(WidgetTester tester) =>
    tester.widgetList<CategoryImage>(find.byType(CategoryImage)).map((w) => w.url);

void main() {
  group('adminCategoryImage', () {
    test('real pictures saved in Admin are used (as full URLs)', () {
      expect(adminCategoryImage(_storageUrl), _storageUrl);
      expect(adminCategoryImage('/images/RO_System.png'), '$_origin/images/RO_System.png');
      expect(adminCategoryImage('/api/product-images/img_1_abc.jpg'), '$_origin/api/product-images/img_1_abc.jpg');
      expect(adminCategoryImage('/uploads/cat_1.png'), '$_origin/uploads/cat_1.png');
      expect(adminCategoryImage('  /images/x.png  '), '$_origin/images/x.png');
    });

    test('old placeholder names and empty values keep the app\'s own picture', () {
      for (final legacy in ['purifier.jpg', 'membrane.jpg', 'cat_filter.jpg', 'cat_pump.jpg', 'cat_spares.jpg', '', '   ', null]) {
        expect(adminCategoryImage(legacy), isNull, reason: '$legacy');
      }
    });

    test('never a localhost address in a production build', () {
      expect(adminCategoryImage('/images/RO_System.png'), isNot(contains('localhost')));
    });
  });

  testWidgets('Home: Admin-saved category images are shown; otherwise the app\'s own picture', (tester) async {
    tester.view.physicalSize = const Size(1440, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        catalogProductsProvider.overrideWith((ref) async => _products),
        catalogCategoriesProvider.overrideWith((ref) async => _categories),
      ],
      child: const MaterialApp(home: HomeScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    HomeCategoryCard card(String id) => tester.widget<HomeCategoryCard>(find.byKey(ValueKey('home-category-$id')));
    // Saved in Admin -> shown; the app's picture stays as the fallback.
    expect(card('systems').imageUrl, '$_origin/images/RO_System_new.png');
    expect(card('systems').fallbackImageUrl, ApiClient.imageUrl('RO_System.png'));
    expect(card('filters').imageUrl, '$_origin/api/product-images/img_1_abc.jpg');
    // Old placeholder name / empty -> unchanged behaviour.
    expect(card('membranes').imageUrl, ApiClient.imageUrl('membrane.webp'));
    expect(card('membranes').fallbackImageUrl, isNull);
    expect(card('pumps').imageUrl, ApiClient.imageUrl('pumps.webp'));
    // Cabinet: its saved picture replaces the water drop.
    expect(card('cabinets').imageUrl, _storageUrl);
    expect(card('cabinets').placeholderIcon, isNull);
    expect(_shownUrls(tester), contains('$_origin/images/RO_System_new.png'));
    expect(_shownUrls(tester).any((u) => u.contains('localhost')), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home: Cabinet without a saved picture keeps the water-drop placeholder', (tester) async {
    tester.view.physicalSize = const Size(1440, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final noCabinetImage = [
      for (final c in _categories)
        c.id == 'cabinets'
            ? const CategoryModel(id: 'cabinets', databaseId: 'CAT_CAB', name: 'Cabinet', imagePath: '', productCount: 1, description: '')
            : c,
    ];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        catalogProductsProvider.overrideWith((ref) async => _products),
        catalogCategoriesProvider.overrideWith((ref) async => noCabinetImage),
      ],
      child: const MaterialApp(home: HomeScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final cabinet = tester.widget<HomeCategoryCard>(find.byKey(const ValueKey('home-category-cabinets')));
    expect(cabinet.imageUrl, isNull);
    expect(cabinet.placeholderIcon, Icons.water_drop_rounded);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Categories page: sidebar and tiles use the Admin-saved image, else the app\'s own picture', (tester) async {
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        catalogProductsProvider.overrideWith((ref) async => _products),
        catalogCategoriesProvider.overrideWith((ref) async => _categories),
        cartProvider.overrideWith((ref) => _EmptyCart()),
      ],
      child: const MaterialApp(home: CategoriesScreen()),
    ));
    await tester.pumpAndSettle();
    final urls = _shownUrls(tester).toList();
    expect(urls, contains('$_origin/images/RO_System_new.png'), reason: 'RO Systems: saved image');
    expect(urls, contains('$_origin/api/product-images/img_1_abc.jpg'), reason: 'Filters: uploaded image');
    expect(urls, contains(_storageUrl), reason: 'Cabinet: saved image instead of the water drop');
    expect(urls, contains(ApiClient.imageUrl('membrane.webp')), reason: 'legacy name: app picture');
    expect(urls, contains(ApiClient.imageUrl('pumps.webp')), reason: 'empty: app picture');
    // The app's own RO picture appears only as the fallback INSIDE the saved
    // image (network images never load in tests, so the fallback is built).
    final saved = find.byWidgetPredicate((w) => w is CategoryImage && w.url == '$_origin/images/RO_System_new.png');
    final builtIn = find.byWidgetPredicate((w) => w is CategoryImage && w.url == ApiClient.imageUrl('RO_System.png'));
    expect(builtIn, findsWidgets);
    expect(find.descendant(of: saved, matching: builtIn).evaluate().length, builtIn.evaluate().length,
        reason: 'never shown instead of the saved image, only as its fallback');
    expect(tester.takeException(), isNull);
  });
}
