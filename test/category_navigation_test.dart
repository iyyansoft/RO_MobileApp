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
    expect(find.text('1 Items'), findsNWidgets(3));
    expect(find.text('0 Items'), findsNothing);
    await tester.tap(find.text('Membranes'));
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

    // Category chips and All Products keep their existing behavior.
    await tester.ensureVisible(
      find.widgetWithText(ChoiceChip, 'Booster Pumps'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Booster Pumps'));
    await tester.pumpAndSettle();
    expect(find.text('API Pump'), findsOneWidget);
    expect(find.text('API Membrane'), findsNothing);
    final horizontalList = find.byWidgetPredicate(
      (widget) =>
          widget is ListView && widget.scrollDirection == Axis.horizontal,
    );
    await tester.dragUntilVisible(
      find.widgetWithText(ChoiceChip, 'Pipes & Tubing'),
      horizontalList,
      const Offset(-200, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Pipes & Tubing'));
    await tester.pumpAndSettle();
    expect(find.text('API Pipe'), findsOneWidget);
    expect(find.text('API Pump'), findsNothing);
    await tester.dragUntilVisible(
      find.widgetWithText(ChoiceChip, 'All Products'),
      horizontalList,
      const Offset(200, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'All Products'));
    await tester.pumpAndSettle();
    expect(find.text('API Membrane'), findsOneWidget);
    expect(find.text('API Pump'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Booster Pumps'));
    await tester.pumpAndSettle();
    expect(find.text('API Pump'), findsOneWidget);
    expect(find.text('API Membrane'), findsNothing);
    expect(container.read(productFilterProvider).searchQuery, 'old search');
    expect(tester.takeException(), isNull);
  });
}
