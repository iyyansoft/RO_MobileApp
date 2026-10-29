import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/core/network/api_client.dart';
import 'package:ro_wholesale_dealer_app/core/theme/app_theme.dart';
import 'package:ro_wholesale_dealer_app/features/auth/domain/models/user_model.dart';
import 'package:ro_wholesale_dealer_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:ro_wholesale_dealer_app/features/cart/presentation/providers/cart_provider.dart';
import 'package:ro_wholesale_dealer_app/features/checkout/presentation/providers/checkout_provider.dart';
import 'package:ro_wholesale_dealer_app/features/checkout/presentation/screens/checkout_screen.dart';
import 'package:ro_wholesale_dealer_app/features/checkout/presentation/screens/order_success_screen.dart';
import 'package:ro_wholesale_dealer_app/features/checkout/data/razorpay_checkout.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_model.dart';

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

class _TestGateway extends RazorpayCheckout {
  @override
  Future<Map<String, String>> pay(
    Map<String, dynamic> order, {
    required String email,
    required String name,
  }) async => {
    'razorpay_order_id': 'gateway_order',
    'razorpay_payment_id': 'gateway_payment',
    'razorpay_signature': 'test_signature',
  };
}

void main() {
  FlutterSecureStorage.setMockInitialValues({});
  testWidgets('checkout displays and selects every supported payment option', (
    tester,
  ) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ApiClient(
      interceptors: [
        InterceptorsWrapper(
          onRequest: (request, handler) => handler.resolve(
            Response(
              requestOptions: request,
              data: {
                'success': true,
                'items': [
                  {
                    'id': 'filter',
                    'name': 'Filter',
                    'price': 900,
                    'quantity': 1,
                    'img': 'assets/images/purifier.jpg',
                  },
                ],
                'addresses': [],
              },
            ),
          ),
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        authProvider.overrideWith((ref) => _SignedIn(api)),
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
    expect(find.text('Company / business name'), findsOneWidget);
    expect(find.text('PAN (optional)'), findsOneWidget);
    expect(
      find.text('Credit/Debit Card, UPI, Net Banking, Wallets'),
      findsOneWidget,
    );
    expect(find.byType(Radio<PaymentMethodType>), findsNWidgets(2));
    expect(find.byIcon(Icons.account_balance_wallet_rounded), findsOneWidget);
    expect(find.byIcon(Icons.local_shipping_rounded), findsOneWidget);
    for (final method in [
      PaymentMethodType.cashOnDelivery,
      PaymentMethodType.razorpay,
    ]) {
      final option = find.text(method.label);
      expect(option, findsOneWidget);
      await tester.ensureVisible(option);
      await tester.pumpAndSettle();
      await tester.tap(option);
      await tester.pumpAndSettle();
      expect(container.read(checkoutProvider).selectedPaymentMethod, method);
    }
    final razorpayContainer = tester.widget<Container>(
      find
          .ancestor(
            of: find.text(PaymentMethodType.razorpay.label),
            matching: find.byType(Container),
          )
          .first,
    );
    final razorpayDecoration = razorpayContainer.decoration! as BoxDecoration;
    expect(razorpayDecoration.border!.top.color, const Color(0xFF3478D4));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const OrderSuccessScreen(
          orderId: 'test-order',
          paymentMethod: PaymentMethodType.razorpay,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Paid'), findsOneWidget);
    expect(find.text('Confirmed'), findsNothing);
    expect(find.text(PaymentMethodType.razorpay.label), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test(
    'single-unit cart changes and checkout use the same quantities and totals',
    () async {
      var quantity = 0;
      final mutations = <RequestOptions>[];
      Map<String, dynamic>? order;
      final product = ProductModel.fromJson({
        'id': 'filter',
        'name': 'Filter',
        'price': 100.55,
        'moq': 10,
      });
      final api = ApiClient(
        interceptors: [
          InterceptorsWrapper(
            onRequest: (request, handler) {
              final data = request.data as Map?;
              if (request.path == 'cart/add') {
                mutations.add(request);
                quantity += data!['quantity'] as int;
              } else if (request.path == 'cart/update') {
                mutations.add(request);
                quantity = data!['quantity'] as int;
              } else if (request.path == 'cart/remove') {
                mutations.add(request);
                quantity = 0;
              } else if (request.path == 'user/orders/create') {
                order = Map<String, dynamic>.from(data!);
              }
              handler.resolve(
                Response(
                  requestOptions: request,
                  data: {
                    'success': true,
                    'items': quantity == 0
                        ? []
                        : [
                            {
                              'id': 'filter',
                              'price': 100.55,
                              'moq': 10,
                              'quantity': quantity,
                            },
                          ],
                    'addresses': [
                      {
                        'id': 'delivery',
                        'fullName': 'Dealer',
                        'phone': '9876543210',
                        'street': 'Test Street',
                        'city': 'Chennai',
                        'state': 'Tamil Nadu',
                        'pincode': '600001',
                        'isDefault': true,
                      },
                    ],
                    'order': {
                      'orderId': 'test-order',
                      'id': 'gateway_order',
                      'amount': 35678,
                      'key': 'test_key',
                    },
                  },
                ),
              );
            },
          ),
        ],
      );
      final cart = CartNotifier(api, 'dealer', catalog: () => [product]);
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          authProvider.overrideWith((ref) => _SignedIn(api)),
          cartProvider.overrideWith((ref) => cart),
          razorpayCheckoutProvider.overrideWithValue(_TestGateway()),
        ],
      );
      addTearDown(container.dispose);
      Future<void> settleCart() async {
        while (cart.state.isLoading) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
      }

      await settleCart();
      await cart.addToCart(product);
      expect(mutations.last.data['quantity'], 1);
      expect(cart.state.totalItemCount, 1);
      expect(cart.state.subtotal, 100.55);
      expect(cart.state.dealerDiscount, 10.06);
      expect(cart.state.gstAmount, 16.29);
      expect(cart.state.grandTotal, 356.78);

      expect(cart.updateQuantity(product.id, 2), isTrue);
      await settleCart();
      expect(cart.state.totalItemCount, 2);
      expect(cart.state.subtotal, 201.10);
      expect(cart.state.gstAmount, 32.58);
      expect(cart.state.grandTotal, 463.57);
      expect(cart.updateQuantity(product.id, 1), isTrue);
      await settleCart();
      final checkout = container.read(checkoutProvider.notifier);
      await checkout.loadAddresses();
      for (final method in [
        PaymentMethodType.cashOnDelivery,
        PaymentMethodType.razorpay,
      ]) {
        checkout.selectPaymentMethod(method);
        expect(
          await checkout.placeOrder(withGst: true, gstin: '27AAPFU0939F1ZV'),
          'test-order',
        );
        expect(order!['paymentMethod'], method.label);
      }
      expect((order!['items'] as List).single['quantity'], 1);
      expect(order!['subtotal'], cart.state.subtotal);
      expect(order!['gst'], cart.state.gstAmount);
      expect(order!['grandTotal'], cart.state.grandTotal);
      expect(order!['razorpay_payment_id'], 'gateway_payment');
      checkout.selectPaymentMethod(PaymentMethodType.cashOnDelivery);
      await expectLater(
        checkout.placeOrder(withGst: true, gstin: 'invalid'),
        throwsStateError,
      );
      expect(await checkout.placeOrder(withGst: false), 'test-order');
      expect(order!['gst'], 0);
      expect(order!['grandTotal'], 340.49);

      expect(cart.updateQuantity(product.id, 0), isTrue);
      await settleCart();
      expect(mutations.last.method, 'DELETE');
      expect(mutations.last.path, 'cart/remove');
      expect(cart.state.items, isEmpty);
      expect(cart.state.subtotal, 0);
      expect(cart.state.gstAmount, 0);
      expect(cart.state.grandTotal, 0);
      await expectLater(checkout.placeOrder(), throwsStateError);
    },
  );
}
