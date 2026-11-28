import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/shop/presentation/shop_screens.dart';
import 'package:ro_wholesale_dealer_app/features/shop/presentation/shop_ui.dart';

bool _passwordHidden(WidgetTester tester) =>
    tester
        .widget<TextField>(find.widgetWithText(TextField, 'Password'))
        .obscureText;

void main() {
  testWidgets('employee sign-in asks for Login ID and password', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ShopEmployeeLoginScreen()));

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/images/neero_logo1.png',
      ),
      findsOneWidget,
    );
    expect(find.text('Welcome Back'), findsOneWidget);
    expect(
      find.text('Sign in to your employee account'),
      findsOneWidget,
    );
    expect(find.text('Employee ID / Login ID'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Forgot Password?'), findsOneWidget);
    expect(find.text('Secure Employee Access'), findsOneWidget);
    // The old split-screen promotion is gone.
    expect(find.text('Shop Employee Login'), findsNothing);
    expect(find.text('SHOP APP'), findsNothing);
    await tester.tap(find.text('Forgot Password?'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Contact your shop admin'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('password can be shown and hidden again', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ShopEmployeeLoginScreen()));
    expect(_passwordHidden(tester), isTrue);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(_passwordHidden(tester), isFalse);
    await tester.tap(find.byTooltip('Hide password'));
    await tester.pump();
    expect(_passwordHidden(tester), isTrue);
  });

  testWidgets('empty submit shows the validation message and sends nothing', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ShopEmployeeLoginScreen()));
    await tester.tap(find.text('Login'));
    await tester.pump();
    expect(find.text('Enter your Employee ID and password.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in const [Size(360, 740), Size(1280, 800)]) {
    testWidgets('fits ${size.width.toInt()} px wide without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(home: ShopEmployeeLoginScreen()),
      );
      await tester.pumpAndSettle();
      final card = tester.getRect(find.byType(ShopPanel));
      expect(card.width, lessThanOrEqualTo(380));
      expect(card.left, greaterThanOrEqualTo(0));
      expect(card.right, lessThanOrEqualTo(size.width));
      expect(card.center.dx, closeTo(size.width / 2, 1));
      expect(tester.takeException(), isNull);
    });
  }
}
