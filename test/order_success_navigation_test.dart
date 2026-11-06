import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ro_wholesale_dealer_app/features/checkout/presentation/providers/checkout_provider.dart';
import 'package:ro_wholesale_dealer_app/features/checkout/presentation/screens/order_success_screen.dart';

GoRouter _router(String initial) => GoRouter(
  initialLocation: initial,
  routes: [
    GoRoute(
      path: '/checkout',
      builder: (context, _) => Scaffold(
        body: TextButton(
          // Mirrors CheckoutScreen after a successful order.
          onPressed: () => context.go(
            OrderSuccessScreen.location(
              orderId: 'abc123',
              withGst: true,
              paymentMethod: PaymentMethodType.razorpay,
            ),
          ),
          child: const Text('Place order'),
        ),
      ),
    ),
    GoRoute(
      path: OrderSuccessScreen.path,
      redirect: (_, state) =>
          OrderSuccessScreen.fromQuery(state.uri.queryParameters) == null
          ? '/orders'
          : null,
      builder: (_, state) =>
          OrderSuccessScreen.fromQuery(state.uri.queryParameters)!,
    ),
    GoRoute(path: '/orders', builder: (_, _) => const Text('Orders page')),
    GoRoute(path: '/home', builder: (_, _) => const Text('Home page')),
  ],
);

Future<GoRouter> _pump(WidgetTester tester, String initial) async {
  await tester.binding.setSurfaceSize(const Size(800, 1000));
  final router = _router(initial);
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('Track Order Status leaves the success screen for Orders', (
    tester,
  ) async {
    await _pump(tester, '/checkout');
    await tester.tap(find.text('Place order'));
    await tester.pumpAndSettle();
    expect(find.text('B2B Wholesale Order Placed!'), findsOneWidget);
    expect(find.text('GST Invoice Generated'), findsOneWidget);
    expect(find.text('Paid'), findsOneWidget);

    await tester.tap(find.text('Track Order Status'));
    await tester.pumpAndSettle();
    expect(find.text('Orders page'), findsOneWidget);
    expect(find.text('B2B Wholesale Order Placed!'), findsNothing);
  });

  testWidgets('Back to Home leaves the success screen for Home', (
    tester,
  ) async {
    await _pump(tester, '/checkout');
    await tester.tap(find.text('Place order'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back to Home'));
    await tester.pumpAndSettle();
    expect(find.text('Home page'), findsOneWidget);
    expect(find.text('B2B Wholesale Order Placed!'), findsNothing);
  });

  testWidgets('refreshing the success URL restores the confirmation', (
    tester,
  ) async {
    await _pump(tester, '/order-success?id=abc123&pay=cashOnDelivery');
    expect(find.text('Due on Delivery'), findsOneWidget);
    expect(find.text('Without GST'), findsOneWidget);
  });

  testWidgets('success URL without an order id falls back to Orders', (
    tester,
  ) async {
    await _pump(tester, '/order-success');
    expect(find.text('Orders page'), findsOneWidget);
  });
}
