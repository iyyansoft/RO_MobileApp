import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/core/network/api_client.dart';
import 'package:ro_wholesale_dealer_app/core/widgets/brand_logo.dart';
import 'package:ro_wholesale_dealer_app/features/cart/domain/models/cart_item_model.dart';
import 'package:ro_wholesale_dealer_app/features/cart/presentation/providers/cart_provider.dart';
import 'package:ro_wholesale_dealer_app/features/main/presentation/screens/main_navigation_screen.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_model.dart';

class _FakeCartNotifier extends CartNotifier {
  _FakeCartNotifier(CartState initialState)
      : super(ApiClient(), 'test-user', catalog: () => []) {
    state = initialState;
  }
  @override
  Future<void> refreshCart() async {}
}

void main() {
  testWidgets(
    'mobile navigation displays all 5 items with badges and highlights correctly',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final product = ProductModel.fromJson({
        'id': 'test-1',
        'name': 'Test Filter',
        'numericPrice': 100,
      });

      final container = ProviderContainer(
        overrides: [
          cartProvider.overrideWith(
            (ref) => _FakeCartNotifier(
              CartState(
                items: [
                  CartItemModel(product: product, quantity: 3),
                ],
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: MainNavigationScreen(
              child: SizedBox(key: ValueKey('home-content')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify all 5 navigation labels are present
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Categories'), findsOneWidget);
      expect(find.text('Orders'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Cart'), findsOneWidget);

      // Verify the cart badge displays '3'
      expect(find.text('3'), findsOneWidget);
    },
  );

  testWidgets(
    'desktop web navigation displays responsive top header with all 5 items and badge',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final product = ProductModel.fromJson({
        'id': 'test-2',
        'name': 'RO Pump',
        'numericPrice': 1200,
      });

      final container = ProviderContainer(
        overrides: [
          cartProvider.overrideWith(
            (ref) => _FakeCartNotifier(
              CartState(
                items: [
                  CartItemModel(product: product, quantity: 5),
                ],
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: MainNavigationScreen(
              child: SizedBox(key: ValueKey('desktop-content')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify desktop brand logo and all 5 navigation items
      expect(find.byType(BrandLogo), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Categories'), findsOneWidget);
      expect(find.text('Orders'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Cart'), findsOneWidget);

      // Verify the cart badge displays '5'
      expect(find.text('5'), findsOneWidget);
    },
  );
}
