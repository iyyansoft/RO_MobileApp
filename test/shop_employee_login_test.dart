import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/shop/presentation/shop_screens.dart';

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
                'assets/images/RO_LOGO.png',
      ),
      findsOneWidget,
    );
    expect(find.text('Shop Employee Login'), findsOneWidget);
    expect(find.text('Employee ID / Login ID'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Forgot Password?'), findsOneWidget);
    await tester.tap(find.text('Forgot Password?'));
    await tester.pumpAndSettle();
    expect(
      find.text('Contact your shop admin to reset your Login ID password.'),
      findsNothing,
    );
    expect(find.textContaining('Contact your shop admin'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
