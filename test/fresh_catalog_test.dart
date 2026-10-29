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
    // The keyed New Arrivals carousel holds the entire catalog.
    final arrivals = find.byKey(const ValueKey('home-products-new_arrivals'));
    await tester.ensureVisible(arrivals);
    await tester.pumpAndSettle();
    final found = <String>{};
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: arrivals, matching: find.byType(Scrollable)).first,
    );
    for (var index = 0; index < 60; index++) {
      for (final product in products) {
        if (find
            .descendant(of: arrivals, matching: find.text(product.name))
            .evaluate()
            .isNotEmpty) {
          found.add(product.id);
        }
      }
      if (scrollable.position.pixels >= scrollable.position.maxScrollExtent) {
        break;
      }
      await tester.drag(arrivals, const Offset(-160, 0));
      await tester.pumpAndSettle();
    }
    expect(found.length, 18);
    expect(tester.takeException(), isNull);
  });
  testWidgets('all six live categories count and open their three products', (
    tester,
  ) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final category in categories) {
      await tester.pumpWidget(scope(const CategoriesScreen()));
      await tester.pumpAndSettle();
      final label = find.text(category.name);
      await tester.scrollUntilVisible(
        label,
        200,
        scrollable: find
            .descendant(
              of: find.byType(GridView),
              matching: find.byType(Scrollable),
            )
            .last,
      );
      await tester.pumpAndSettle();
      await tester.tap(label);
      await tester.pumpAndSettle();
      final expected = products.where(category.matchesProduct).toList();
      expect(expected.length, 3);
      for (final product in expected) {
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
        expect(find.text(product.name), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
  });
}
