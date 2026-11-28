import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ro_wholesale_dealer_app/core/network/api_client.dart';
import 'package:ro_wholesale_dealer_app/core/widgets/app_scroll_behavior.dart';
import 'package:ro_wholesale_dealer_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:ro_wholesale_dealer_app/features/cart/presentation/providers/cart_provider.dart';
import 'package:ro_wholesale_dealer_app/features/home/presentation/screens/home_screen.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/category_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/providers/product_provider.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/screens/categories_screen.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/screens/product_listing_screen.dart';

void main() {
  final live = File('build/fresh-catalog-live.json');
  final captured = live.existsSync()
      ? live
      : File('test/fixtures/fresh_catalog.json');
  final data = jsonDecode(captured.readAsStringSync()) as Map;
  final products = (data['products'] as List)
      .map((p) => ProductModel.fromJson(Map<String, dynamic>.from(p as Map)))
      .toList();
  final categories = (data['categories'] as List)
      .map((c) => CategoryModel.fromJson(Map<String, dynamic>.from(c as Map)))
      .toList();
  ProviderScope scope(Widget screen) {
    final api = ApiClient(
      interceptors: [
        InterceptorsWrapper(
          onRequest: (request, handler) => handler.resolve(
            Response(
              requestOptions: request,
              data: {'success': true, 'items': []},
            ),
          ),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        catalogProductsProvider.overrideWith((ref) async => products),
        catalogCategoriesProvider.overrideWith((ref) async => categories),
        authProvider.overrideWith((ref) => AuthNotifier(api)),
        cartProvider.overrideWith((ref) => CartNotifier(api, '')),
      ],
      child: MaterialApp(
        scrollBehavior: const AppScrollBehavior(),
        home: screen,
      ),
    );
  }

  testWidgets('all 18 live sample products are reachable on Home', (
    tester,
  ) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await tester.pumpWidget(scope(const HomeScreen()));
    await tester.pumpAndSettle();
    // New Arrivals (a 4-item grid since the NeeroPlus redesign) shows the
    // four newest products.
    final arrivals = find.byKey(const ValueKey('home-grid-new_arrivals'));
    await tester.ensureVisible(arrivals);
    await tester.pumpAndSettle();
    for (final product in ProductModel.newestFirst(products).take(4)) {
      expect(
        find.descendant(of: arrivals, matching: find.text(product.name)),
        findsWidgets,
        reason: product.name,
      );
    }
    // Every product is reachable from Home through its category card.
    final found = <String>{};
    for (final category in categories) {
      await tester.pumpWidget(scope(const HomeScreen()));
      await tester.pumpAndSettle();
      final card = find.byKey(ValueKey('home-category-${category.id}'));
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(find.byType(ProductListingScreen), findsOneWidget, reason: category.name);
      for (final product in products.where(category.matchesProduct)) {
        await tester.scrollUntilVisible(
          find.text(product.name),
          200,
          scrollable: find
              .descendant(
                of: find.byType(ProductListingScreen),
                matching: find.byType(Scrollable),
              )
              .last,
        );
        found.add(product.id);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
    expect(found.length, 18);
    expect(tester.takeException(), isNull);
  });
  testWidgets('all six live categories count and open their three products', (
    tester,
  ) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    // Tall window: a category's three products are all on screen.
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final category in categories) {
      await tester.pumpWidget(scope(const CategoriesScreen()));
      await tester.pumpAndSettle();
      // The category is selected in place (sidebar), with its live count.
      final item = find.byKey(ValueKey('category-sidebar-${category.id}'));
      await tester.ensureVisible(item);
      await tester.pumpAndSettle();
      await tester.tap(item);
      await tester.pumpAndSettle();
      final expected = products.where(category.matchesProduct).toList();
      expect(expected.length, 3);
      expect(find.text('3 Wholesale Items Available'), findsOneWidget, reason: category.name);
      for (final product in expected) {
        expect(find.text(product.name), findsWidgets, reason: product.name);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
  });
}
