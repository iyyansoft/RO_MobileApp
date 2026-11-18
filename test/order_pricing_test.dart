import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ro_wholesale_dealer_app/core/network/api_client.dart';
import 'package:ro_wholesale_dealer_app/core/theme/app_theme.dart';
import 'package:ro_wholesale_dealer_app/features/auth/domain/models/user_model.dart';
import 'package:ro_wholesale_dealer_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:ro_wholesale_dealer_app/features/cart/domain/models/cart_item_model.dart';
import 'package:ro_wholesale_dealer_app/features/cart/domain/order_pricing.dart';
import 'package:ro_wholesale_dealer_app/features/cart/presentation/providers/cart_provider.dart';
import 'package:ro_wholesale_dealer_app/features/cart/presentation/screens/cart_screen.dart';
import 'package:ro_wholesale_dealer_app/features/checkout/presentation/screens/checkout_screen.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_model.dart';

final _fixture =
    jsonDecode(File('test/fixtures/pricing_scenarios.json').readAsStringSync())
        as Map<String, dynamic>;

PricingRules _rules(Map<String, dynamic>? json) =>
    PricingRules.fromJson(json ?? _fixture['defaultRules'] as Map<String, dynamic>);

Map<String, num> _pick(OrderTotals t) => {
  'subtotal': t.subtotal,
  'discount': t.discount,
  'gst': t.gst,
  'deliveryFee': t.deliveryFee,
  'grandTotal': t.grandTotal,
};

ProductModel _product(String id, String name, double price) => ProductModel(
  id: id,
  name: name,
  sku: 'SKU-$id',
  categoryId: 'spares',
  categoryName: 'Spares',
  brand: 'RO Wholesale',
  mrp: price * 1.3,
  dealerPrice: price,
  imageUrl: 'assets/images/RO_System.png',
  stockStatus: StockStatus.inStock,
  moq: 1,
);

/// Cart whose state the test sets directly (no backend calls).
class _FakeCart extends CartNotifier {
  _FakeCart(List<CartItemModel> items)
    : super(ApiClient(), 'dealer', catalog: () => []) {
    state = CartState(items: items);
  }

  @override
  Future<void> refreshCart() async {}

  void set(List<CartItemModel> items) => state = CartState(items: items);
}

class _SignedIn extends AuthNotifier {
  _SignedIn(super.api) {
    state = AuthState(
      isLoggedIn: true,
      currentUser: UserModel.fromJson({
        'id': 'dealer',
        'name': 'Dealer',
        'email': 'dealer@example.test',
      }),
    );
  }
}

/// API returning [rules] for GET pricing-rules and an empty success otherwise.
ApiClient _api(Map<String, dynamic> rules) => ApiClient(
  interceptors: [
    InterceptorsWrapper(
      onRequest: (request, handler) => handler.resolve(
        Response(
          requestOptions: request,
          data: request.path.contains('pricing-rules')
              ? {'success': true, 'rules': rules}
              : {'success': true, 'items': [], 'addresses': []},
        ),
      ),
    ),
  ],
);

void main() {
  FlutterSecureStorage.setMockInitialValues({});

  group('shared pricing scenarios (same file as the Node backend test)', () {
    test('fallback rules equal the backend defaults', () {
      expect(_rules(null), PricingRules.fallback);
    });

    for (final raw in _fixture['scenarios'] as List) {
      final s = raw as Map<String, dynamic>;
      test(s['name'], () {
        final rules = _rules(s['rules'] as Map<String, dynamic>?);
        final lines = [
          for (final l in s['lines'] as List)
            (
              unitPrice: (l['unitPrice'] as num).toDouble(),
              quantity: l['quantity'] as int,
            ),
        ];
        for (final (withGst, key) in [(false, 'without'), (true, 'with')]) {
          final totals = OrderTotals.compute(lines, rules: rules, withGst: withGst);
          final expected = (s[key] as Map).map(
            (k, v) => MapEntry(k as String, v as num),
          );
          expect(_pick(totals), expected, reason: key);
          expect(
            totals.grandTotalPaise,
            totals.subtotalPaise -
                totals.discountPaise +
                totals.gstPaise +
                totals.deliveryPaise,
          );
        }
      });
    }
  });

  test('invalid lines are ignored and an empty cart costs nothing', () {
    final rules = PricingRules.fallback;
    final empty = OrderTotals.compute(const [], rules: rules, withGst: true);
    expect(_pick(empty).values.every((v) => v == 0), isTrue);
    expect(empty.freeDelivery, isFalse);
    final mixed = OrderTotals.compute(
      [
        (unitPrice: 100.0, quantity: 2),
        (unitPrice: -50.0, quantity: 1),
        (unitPrice: 30.0, quantity: 0),
        (unitPrice: double.nan, quantity: 1),
      ],
      rules: rules,
    );
    expect(mixed.subtotal, 200);
    expect(mixed.itemCount, 2);
  });

  test('rupee formatting and labels', () {
    expect(formatInr(290), '₹290.00');
    expect(formatInr(43934.94), '₹43,934.94');
    expect(formatInr(125000.5), '₹1,25,000.50');
    expect(formatInr(12345678.9), '₹1,23,45,678.90');
    expect(formatInr(0.3), '₹0.30');
    expect(discountLabel(PricingRules.fallback), 'Gold Dealer Discount (10%)');
    expect(
      discountLabel(_rules({'dealerDiscountPercent': 12.5, 'dealerTierLabel': 'Silver Dealer'})),
      'Silver Dealer Discount (12.5%)',
    );
  });

  test('invalid server rules fall back safely', () {
    final rules = PricingRules.fromJson({
      'dealerDiscountPercent': 'abc',
      'gstPercent': -4,
      'deliveryCharge': 99,
      'freeDeliveryAbove': null,
    });
    expect(rules.dealerDiscountPercent, 10);
    expect(rules.gstPercent, 18);
    expect(rules.deliveryCharge, 99);
    expect(rules.freeDeliveryAbove, 5000);
  });

  testWidgets(
    'cart screen uses the server rules and updates on quantity, delete and clear',
    (tester) async {
      GoogleFonts.config.allowRuntimeFetching = false;
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final housing = _product('housing', 'RO Filter Housing 10 Inch', 290);
      final pump = _product('pump', 'RO Booster Pump 100 GPD', 1450);
      final cart = _FakeCart([CartItemModel(product: housing, quantity: 1)]);
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(
            _api({
              'dealerDiscountPercent': 12.5,
              'dealerTierLabel': 'Silver Dealer',
              'gstPercent': 18,
              'deliveryCharge': 150,
              'freeDeliveryAbove': 3000,
            }),
          ),
          cartProvider.overrideWith((ref) => cart),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const CartScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 290 - 12.5% (36.25) + 150 delivery; no GST in the cart.
      expect(find.text('Silver Dealer Discount (12.5%)'), findsOneWidget);
      expect(find.text('- ₹36.25'), findsOneWidget);
      expect(find.text('Added at checkout'), findsOneWidget);
      expect(find.text('₹150.00'), findsOneWidget);
      expect(find.text('₹403.75'), findsOneWidget);

      // Quantity 3 + another product: 870 + 1450 = 2320.
      cart.set([
        CartItemModel(product: housing, quantity: 3),
        CartItemModel(product: pump, quantity: 1),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Subtotal (4 Pcs)'), findsOneWidget);
      expect(find.text('₹2,320.00'), findsWidgets);
      expect(find.text('- ₹290.00'), findsOneWidget);
      expect(find.text('₹2,180.00'), findsOneWidget);

      // Quantity 3 pumps: 870 + 4350 = 5220 -> free delivery above 3000.
      cart.set([
        CartItemModel(product: housing, quantity: 3),
        CartItemModel(product: pump, quantity: 3),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('FREE'), findsOneWidget);
      expect(find.text('₹4,567.50'), findsOneWidget); // 5220 - 652.50

      // Delete the pump.
      cart.set([CartItemModel(product: housing, quantity: 3)]);
      await tester.pumpAndSettle();
      expect(find.text('₹911.25'), findsOneWidget); // 870 - 108.75 + 150

      // Clear the cart.
      cart.set(const []);
      await tester.pumpAndSettle();
      expect(find.text('Order Cost Summary'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('checkout totals switch correctly between Without and With GST', (
    tester,
  ) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    tester.view.physicalSize = const Size(1280, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _api(
      (_fixture['defaultRules'] as Map).cast<String, dynamic>(),
    );
    final cart = _FakeCart([
      CartItemModel(
        product: _product('housing', 'RO Filter Housing 10 Inch', 290),
        quantity: 1,
      ),
    ]);
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        authProvider.overrideWith((ref) => _SignedIn(api)),
        cartProvider.overrideWith((ref) => cart),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const CheckoutScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Without GST (default): 290 - 29 + 0 + 250 = 511.
    expect(find.text('Grand Total (Without GST)'), findsOneWidget);
    expect(find.text('GST (Without GST)'), findsOneWidget);
    expect(find.text('+ ₹0.00'), findsOneWidget);
    expect(find.text('₹511.00'), findsWidgets);
    expect(find.text('₹464.02'), findsNothing); // the old, wrong total

    // With GST: 290 - 29 + 46.98 + 250 = 557.98.
    final withGst = find.text('With GST');
    await tester.ensureVisible(withGst);
    await tester.tap(withGst);
    await tester.pumpAndSettle();
    expect(find.text('Grand Total (With GST)'), findsOneWidget);
    expect(find.text('GST (18% on ₹261.00)'), findsOneWidget);
    expect(find.text('+ ₹46.98'), findsOneWidget);
    expect(find.text('₹557.98'), findsWidgets);

    // Quantity change updates checkout immediately (2 x 290 = 580).
    cart.set([
      CartItemModel(
        product: _product('housing', 'RO Filter Housing 10 Inch', 290),
        quantity: 2,
      ),
    ]);
    await tester.pumpAndSettle();
    // 580 - 58 = 522; GST 93.96; +250 = 865.96.
    expect(find.text('+ ₹93.96'), findsOneWidget);
    expect(find.text('₹865.96'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
