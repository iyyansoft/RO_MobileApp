import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/app/config/router/app_router.dart';
import 'package:ro_wholesale_dealer_app/features/admin/presentation/screens/admin_screen.dart';

void main() {
  // Tests run like the Android app (not web): /admin must never open there.
  testWidgets('the Admin Dashboard is web-only: /admin redirects on Android', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: AppRouter.router)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    AppRouter.router.go('/admin');
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(AdminScreen), findsNothing);
    expect(
      AppRouter.router.routerDelegate.currentConfiguration.uri.path,
      isNot(startsWith('/admin')),
    );
  });
}
