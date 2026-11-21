import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/core/widgets/app_toast.dart';

void main() {
  late BuildContext ctx;

  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            ctx = context;
            return const Scaffold(body: SizedBox.expand());
          },
        ),
      ),
    );
  }

  final message = find.byKey(const ValueKey('app-toast-message'));

  testWidgets('success toast: compact, auto-dismisses after 3 s', (
    tester,
  ) async {
    await pump(tester, const Size(1366, 900));
    var viewed = 0;
    AppToast.success(
      ctx,
      'Product added to cart successfully',
      actionLabel: 'View Cart',
      onAction: () => viewed++,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Product added to cart successfully'), findsOneWidget);
    expect(find.text('View Cart'), findsOneWidget);
    // Desktop: bottom-right, compact (not full width).
    final rect = tester.getRect(
      find.ancestor(of: message, matching: find.byType(Material)).first,
    );
    expect(rect.width, lessThanOrEqualTo(380));
    expect(rect.right, closeTo(1366 - 24, 1));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(message, findsNothing, reason: 'gone after 3 s');
    expect(viewed, 0);
  });

  testWidgets('no duplicates; a new message replaces the old one', (
    tester,
  ) async {
    await pump(tester, const Size(390, 844));
    for (var i = 0; i < 3; i++) {
      AppToast.success(ctx, 'Product added to cart successfully');
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(message, findsOneWidget, reason: 'one toast, not three');
    AppToast.error(ctx, 'Only 2 of Pump in stock.');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(message, findsOneWidget);
    expect(find.text('Only 2 of Pump in stock.'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    // Mobile: above the bottom bars, not at the very bottom.
    final rect = tester.getRect(message);
    expect(rect.bottom, lessThan(844 - 96));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(message, findsNothing);
  });

  testWidgets('View Cart runs its action and closes the toast', (tester) async {
    await pump(tester, const Size(1366, 900));
    var viewed = 0;
    AppToast.success(
      ctx,
      'Product added to cart successfully',
      actionLabel: 'View Cart',
      onAction: () => viewed++,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('View Cart'));
    await tester.pumpAndSettle();
    expect(viewed, 1);
    expect(message, findsNothing);
  });
}
