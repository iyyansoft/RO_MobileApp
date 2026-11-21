import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ro_wholesale_dealer_app/app/config/router/app_router.dart';
import 'package:ro_wholesale_dealer_app/core/network/api_client.dart';
import 'package:ro_wholesale_dealer_app/core/widgets/brand_logo.dart';
import 'package:ro_wholesale_dealer_app/features/cart/presentation/providers/cart_provider.dart';
import 'package:ro_wholesale_dealer_app/features/main/presentation/screens/main_navigation_screen.dart';

class _EmptyCart extends CartNotifier {
  _EmptyCart() : super(ApiClient(), 'dealer', catalog: () => []);
  @override
  Future<void> refreshCart() async {}
}

/// Every path declared under [routes] (with nested paths joined).
List<String> _paths(List<RouteBase> routes, [String parent = '']) => [
  for (final r in routes)
    if (r is GoRoute) ...[
      r.path.startsWith('/') ? r.path : '$parent/${r.path}',
      ..._paths(
        r.routes,
        r.path.startsWith('/') ? r.path : '$parent/${r.path}',
      ),
    ] else if (r is ShellRoute)
      ..._paths(r.routes, parent),
];

void main() {
  test('every customer page is inside the navbar shell (app_router.dart)', () {
    final routes = AppRouter.router.configuration.routes;
    final shell = routes.whereType<ShellRoute>().single;
    expect(shell.navigatorKey, same(MainNavigationScreen.shellNavigatorKey));
    final inShell = _paths(shell.routes);
    for (final path in [
      '/home',
      '/products',
      '/products/:id',
      '/categories',
      '/bulk-orders',
      '/bulk-orders/product/:id',
      '/cart',
      '/checkout',
      '/order-success',
      '/orders',
      '/profile',
      '/wishlist',
    ]) {
      expect(inShell, contains(path), reason: '$path shows the navbar');
    }
    // Outside the shell: sign-in screens, admin, Shop app only.
    final outside = routes.whereType<GoRoute>().map((r) => r.path).toSet();
    expect(outside.intersection(inShell.toSet()), isEmpty);
    expect(outside, containsAll(['/login', '/admin', '/splash']));
  });

  testWidgets('a page opened from a tab keeps the navbar; tapping the tab '
      'closes it', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        ShellRoute(
          navigatorKey: MainNavigationScreen.shellNavigatorKey,
          builder: (_, __, child) => MainNavigationScreen(child: child),
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, _) => Scaffold(
                body: Center(
                  child: TextButton(
                    // Same as the app: opened on the shell's navigator.
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const Scaffold(
                          body: Center(child: Text('PRODUCT DETAILS')),
                        ),
                      ),
                    ),
                    child: const Text('OPEN PRODUCT'),
                  ),
                ),
              ),
            ),
            for (final p in ['products', 'orders', 'profile', 'cart'])
              GoRoute(
                path: '/$p',
                builder: (_, __) => Text('${p.toUpperCase()} PAGE'),
              ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [cartProvider.overrideWith((ref) => _EmptyCart())],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('OPEN PRODUCT'));
    await tester.pumpAndSettle();
    expect(find.text('PRODUCT DETAILS'), findsOneWidget);
    // The navbar (logo + items) is still there, once.
    expect(find.byType(BrandLogo), findsOneWidget);
    expect(find.text('Categories'), findsOneWidget);
    // Home is already the address: tapping it still closes the product page.
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('PRODUCT DETAILS'), findsNothing);
    expect(find.text('OPEN PRODUCT'), findsOneWidget);
    // Another tab works as before.
    await tester.tap(find.text('Orders'));
    await tester.pumpAndSettle();
    expect(find.text('ORDERS PAGE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
