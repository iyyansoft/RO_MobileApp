import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ro_wholesale_dealer_app/app/config/router/app_router.dart';

void main() {
  // Product details is inside the shell (MainNavigationScreen), so the main
  // navbar is shown on it like on every other customer page.
  test('product details route belongs to the navbar shell', () {
    final routes = AppRouter.router.configuration.routes;
    expect(
      routes.whereType<GoRoute>().any((route) => route.path == '/products/:id'),
      isFalse,
      reason: 'not above the shell (that hid the navbar)',
    );
    final shell = routes.whereType<ShellRoute>().single;
    final shellPaths = shell.routes
        .whereType<GoRoute>()
        .map((r) => r.path)
        .toSet();
    expect(
      shellPaths,
      containsAll([
        '/home',
        '/products',
        '/products/:id',
        '/categories',
        '/orders',
        '/profile',
        '/cart',
        '/checkout',
      ]),
    );
  });
}
