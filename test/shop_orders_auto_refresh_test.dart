import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/shop/data/shop_employee_repository.dart';
import 'package:ro_wholesale_dealer_app/features/shop/presentation/shop_screens.dart';

/// Stands in for GET /api/shop/orders on the shared backend.
class _Backend {
  final orders = <Map<String, dynamic>>[];
  var requests = 0;
  var offline = false;

  ShopEmployeeRepository repo() {
    final dio = Dio(BaseOptions(baseUrl: 'http://shop.test/api/'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests++;
          if (offline) {
            return handler.reject(
              DioException.connectionError(
                requestOptions: options,
                reason: 'offline',
              ),
            );
          }
          handler.resolve(
            Response(
              requestOptions: options,
              data: {'success': true, 'orders': orders},
            ),
          );
        },
      ),
    );
    return ShopEmployeeRepository.forTesting(dio);
  }

  void place(String id, String customer, String product) => orders.insert(0, {
    'orderId': id,
    'vendorName': customer,
    'companyName': 'SRP',
    'orderDate': DateTime.now().toIso8601String(),
    'paymentMethod': 'Cash on Delivery',
    'paymentStatus': 'due_on_delivery',
    'status': 'Pending',
    'items': [
      {
        'id': '${orders.length + 1}',
        'name': product,
        'sku': 'SKU',
        'unitPrice': 290,
        'quantity': 1,
        'image': '',
      },
    ],
  });
}

Future<void> _pump(
  WidgetTester tester,
  ShopEmployeeRepository repo, {
  bool active = true,
}) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ShopOrdersScreen(
          repo: repo,
          active: active,
          refreshInterval: const Duration(seconds: 5),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a newly placed customer order appears without pressing Refresh', (
    tester,
  ) async {
    final backend = _Backend()..place('D4BS5R', 'Priya', 'RO Filter Housing 10 Inch');
    await _pump(tester, backend.repo());
    expect(find.text('Priya'), findsOneWidget);
    expect(find.textContaining('NEW001'), findsNothing);

    // Customer places an order in the main app.
    backend.place('NEW001', 'Karthik', 'RO Membrane 75 GPD');
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(find.textContaining('NEW001'), findsOneWidget);
    expect(find.text('Karthik'), findsOneWidget);
    expect(find.textContaining('RO Membrane 75 GPD'), findsOneWidget);
    expect(find.text('2 orders'), findsOneWidget);
    // Background refresh does not show the loading bar.
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('a hidden orders page does not poll, and refreshes when shown', (
    tester,
  ) async {
    final backend = _Backend()..place('D4BS5R', 'Priya', 'RO Filter Housing 10 Inch');
    final repo = backend.repo();
    await _pump(tester, repo, active: false);
    final afterFirstLoad = backend.requests;

    await tester.pump(const Duration(seconds: 15));
    expect(backend.requests, afterFirstLoad, reason: 'hidden page stays quiet');

    backend.place('NEW002', 'Karthik', 'Booster Pump');
    await _pump(tester, repo);
    expect(find.textContaining('NEW002'), findsOneWidget);
  });

  testWidgets('a failed background refresh keeps the orders on screen', (
    tester,
  ) async {
    final backend = _Backend()..place('D4BS5R', 'Priya', 'RO Filter Housing 10 Inch');
    await _pump(tester, backend.repo());
    backend.offline = true;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.textContaining('D4BS5R'), findsOneWidget);
    expect(find.text('Could not load shop data'), findsNothing);
  });
}
