import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ro_wholesale_dealer_app/app/config/router/app_router.dart';

void main() {
  test('product details route belongs to the root navigator', () {
    final routes = AppRouter.router.configuration.routes;
    expect(
      routes.whereType<GoRoute>().any((route) => route.path == '/products/:id'),
      isTrue,
    );
    for (final shell in routes.whereType<ShellRoute>()) {
      expect(
        shell.routes.whereType<GoRoute>().any(
          (route) => route.path == '/products/:id',
        ),
        isFalse,
      );
    }
  });
}
