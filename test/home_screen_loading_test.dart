import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:ro_wholesale_dealer_app/core/network/api_client.dart';
import 'package:ro_wholesale_dealer_app/core/widgets/app_scroll_behavior.dart';
import 'package:ro_wholesale_dealer_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:ro_wholesale_dealer_app/features/cart/presentation/providers/cart_provider.dart';
import 'package:ro_wholesale_dealer_app/features/home/presentation/screens/home_screen.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/category_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/providers/product_provider.dart';

Finder _homeLogo() => find.byWidgetPredicate(
  (widget) =>
      widget is Image &&
      widget.image is AssetImage &&
      (widget.image as AssetImage).assetName == 'assets/images/RO_LOGO.png',
);

const _products = [
  ProductModel(
    id: 'featured-one',
    name: 'Featured Filter One',
    sku: 'FILTER-1',
    categoryId: 'filters',
    categoryName: 'Filters',
    brand: 'Aqua',
    mrp: 100,
    dealerPrice: 60,
    imageUrl: 'assets/images/purifier.jpg',
    stockStatus: StockStatus.inStock,
    moq: 1,
    isFeatured: true,
  ),
  ProductModel(
    id: 'featured-two',
    name: 'Featured Filter Two',
    sku: 'FILTER-2',
    categoryId: 'filters',
    categoryName: 'Filters',
    brand: 'Aqua',
    mrp: 100,
    dealerPrice: 65,
    imageUrl: 'assets/images/purifier.jpg',
    stockStatus: StockStatus.inStock,
    moq: 10,
  ),
  ProductModel(
    id: 'featured-three',
    name: 'Featured Filter Three',
    sku: 'FILTER-3',
    categoryId: 'filters',
    categoryName: 'Filters',
    brand: 'Aqua',
    mrp: 100,
    dealerPrice: 70,
    imageUrl: 'assets/images/purifier.jpg',
    stockStatus: StockStatus.inStock,
    moq: 1,
    isFeatured: true,
  ),
];

CartNotifier _cartWithoutNetwork() => CartNotifier(
  ApiClient(
    interceptors: [
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.resolve(
          Response(requestOptions: options, data: const {'items': []}),
        ),
      ),
    ],
  ),
  '',
);

void main() {
  testWidgets('Home remains visible while catalog loads, then shows products', (
    tester,
  ) async {
    final products = Completer<List<ProductModel>>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogProductsProvider.overrideWith((ref) => products.future),
          catalogCategoriesProvider.overrideWith(
            (ref) async => const <CategoryModel>[],
          ),
          authProvider.overrideWith((ref) => AuthNotifier(ApiClient())),
          cartProvider.overrideWith((ref) => _cartWithoutNetwork()),
        ],
        child: const MaterialApp(
          scrollBehavior: AppScrollBehavior(),
          home: HomeScreen(),
        ),
      ),
    );

    expect(_homeLogo(), findsOneWidget);
    expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.shopping_cart_outlined), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    products.complete(_products);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Featured Wholesale Deals'), findsOneWidget);
    expect(find.text('Best Sellers'), findsOneWidget);
    expect(find.text('New Arrivals 2026'), findsOneWidget);
    expect(find.text('Bulk MOQ Deals (Max Discount)'), findsOneWidget);
    final horizontalLists = find.byWidgetPredicate(
      (widget) =>
          widget is ListView && widget.scrollDirection == Axis.horizontal,
    );
    // Home category cards now use a grid; every horizontal list is a product carousel.
    for (var index = 0; index < horizontalLists.evaluate().length; index++) {
      final list = horizontalLists.at(index);
      await tester.ensureVisible(list);
      await tester.pumpAndSettle();
      await tester.drag(list, const Offset(-600, 0));
      await tester.pumpAndSettle();
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)).first,
      );
      expect(scrollable.position.pixels, scrollable.position.maxScrollExtent);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home keeps its header and offers retry when catalog fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogProductsProvider.overrideWith(
            (ref) async => throw StateError('offline'),
          ),
          catalogCategoriesProvider.overrideWith(
            (ref) async => const <CategoryModel>[],
          ),
          authProvider.overrideWith((ref) => AuthNotifier(ApiClient())),
          cartProvider.overrideWith((ref) => _cartWithoutNetwork()),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(_homeLogo(), findsOneWidget);
    expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.shopping_cart_outlined), findsOneWidget);
    expect(find.text('We couldn’t load the product catalog'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
