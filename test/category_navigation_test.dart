import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ro_wholesale_dealer_app/core/theme/app_theme.dart';
import 'package:ro_wholesale_dealer_app/core/widgets/app_scroll_behavior.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/category_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/providers/product_provider.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/screens/categories_screen.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/screens/product_listing_screen.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/screens/product_details_screen.dart';

void main() {
  testWidgets('category taps open API products without stale listing filters', (
    tester,
  ) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    tester.view.physicalSize = const Size(411, 914);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // The API exposes both a database ID and the key used by products.
    final categories = [
      CategoryModel.fromJson({
        'id': 'CAT_MEM',
        'key_name': 'membranes',
        'title': 'Membranes',
        'image_url': 'assets/images/purifier.jpg',
      }),
      CategoryModel.fromJson({
        'id': 'CAT_PMP',
        'key_name': 'pumps',
        'title': 'Booster Pumps',
        'image_url': 'assets/images/purifier.jpg',
      }),
      CategoryModel.fromJson({
        'id': 'CAT_PIP',
        'key_name': 'pipes',
        'title': 'Pipes & Tubing',
        'image_url': 'assets/images/purifier.jpg',
      }),
    ];
    final products = [
      ProductModel.fromJson({
        'id': 'membrane-1',
        'name': 'API Membrane',
        'category': 'membranes',
        'price': 1500,
        'moq': 10,
        'img': 'assets/images/purifier.jpg',
      }),
      ProductModel.fromJson({
        'id': 'pump-1',
        'name': 'API Pump',
        'category': 'pumps',
        'price': 2500,
        'img': 'assets/images/purifier.jpg',
      }),
      ProductModel.fromJson({
        'id': 'pipe-1',
        'name': 'API Pipe',
        'category': 'pipes',
        'price': 100,
        'img': 'assets/images/purifier.jpg',
      }),
    ];
    final container = ProviderContainer(
      overrides: [
        catalogCategoriesProvider.overrideWith((ref) async => categories),
        catalogProductsProvider.overrideWith((ref) async => products),
      ],
    );
    addTearDown(container.dispose);
    container.read(productFilterProvider.notifier)
      ..setSearchQuery('old search')
      ..selectCategory('pumps')
      ..toggleBrand('old brand')
      ..setPriceRange(10000, 20000);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          scrollBehavior: const AppScrollBehavior(),
          theme: AppTheme.lightTheme,
          home: const CategoriesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Every category (API key + database id) counts and lists its own API
    // product, despite the stale global filters (category "pumps", brand,
    // price 10,000–20,000, search) — those must not hide or move anything.
    for (final (key, name, own, other) in [
      ('pumps', 'Booster Pumps', 'API Pump', 'API Membrane'),
      ('pipes', 'Pipes & Tubing', 'API Pipe', 'API Pump'),
      ('membranes', 'Membranes', 'API Membrane', 'API Pump'),
    ]) {
      await tester.ensureVisible(find.byKey(ValueKey('category-sidebar-$key')));
      await tester.tap(find.byKey(ValueKey('category-sidebar-$key')));
      await tester.pumpAndSettle();
      expect(find.text('1 Wholesale Items Available'), findsOneWidget, reason: name);
      expect(find.text('0 Wholesale Items Available'), findsNothing);
      expect(find.text(own), findsOneWidget, reason: name);
      expect(find.text(other), findsNothing, reason: name);
    }
    // The category tiles select a category too.
    await tester.tap(find.byKey(const ValueKey('category-sidebar-for_you')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('popular-store-membranes')));
    await tester.tap(find.byKey(const ValueKey('popular-store-membranes')));
    await tester.pumpAndSettle();
    expect(find.text('API Membrane'), findsOneWidget);

    // "View All" opens the full listing for that category.
    await tester.tap(find.text('View All').first);
    await tester.pumpAndSettle();
    final listing = tester.widget<ProductListingScreen>(
      find.byType(ProductListingScreen),
    );
    expect(listing.initialCategoryId, 'membranes');
    expect(listing.initialCategoryName, 'Membranes');
    expect(find.text('API Membrane'), findsOneWidget);
    expect(find.text('API Pump'), findsNothing);
    await tester.tap(find.text('API Membrane'));
    await tester.pumpAndSettle();
    expect(find.byType(ProductDetailsScreen), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    await tester.ensureVisible(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.remove_rounded));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();

    // Category chips (scrolling row) and All Products keep their behaviour.
    Future<void> tapChip(String id) async {
      await tester.ensureVisible(find.byKey(ValueKey('category-chip-$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('category-chip-$id')));
      await tester.pumpAndSettle();
    }

    await tapChip('pumps');
    expect(find.text('API Pump'), findsOneWidget);
    expect(find.text('API Membrane'), findsNothing);
    await tapChip('pipes');
    expect(find.text('API Pipe'), findsOneWidget);
    expect(find.text('API Pump'), findsNothing);
    await tapChip('all');
    expect(find.text('API Membrane'), findsOneWidget);
    expect(find.text('API Pump'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('category-sidebar-pumps')));
    await tester.tap(find.byKey(const ValueKey('category-sidebar-pumps')));
    await tester.pumpAndSettle();
    expect(find.text('API Pump'), findsOneWidget);
    expect(find.text('API Membrane'), findsNothing);
    expect(container.read(productFilterProvider).searchQuery, 'old search');
    expect(tester.takeException(), isNull);
  });
}
