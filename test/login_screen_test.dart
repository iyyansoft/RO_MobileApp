import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/core/widgets/brand_logo.dart';
import 'package:ro_wholesale_dealer_app/features/auth/presentation/screens/login_screen.dart';

void main() {
  testWidgets('email sign in validates before sending a code', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LoginScreen())),
    );
    await tester.enterText(find.byType(TextFormField).first, 'invalid-email');
    await tester.tap(find.text('Send sign in code'));
    await tester.pump();
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('Create a dealer account'), findsOneWidget);
    expect(find.text('Admin sign in'), findsNothing);
    expect(find.text('Shop Employee Login'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('password login requires a password on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LoginScreen())),
    );
    await tester.ensureVisible(find.text('Sign in with password'));
    await tester.tap(find.text('Sign in with password'));
    await tester.pump();
    await tester.enterText(
      find.byType(TextFormField).first,
      'dealer@example.com',
    );
    await tester.ensureVisible(find.text('Sign in').last);
    await tester.tap(find.text('Sign in').last);
    await tester.pump();
    expect(find.text('Enter password'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // The sign-in page (NeeroPlus redesign, Nov 2026) is one centred card, at
  // most 480 px wide, on every screen size: brand logo, "Welcome Back", a
  // code/password switch, the form and the account links.
  Rect signInCard(WidgetTester tester) => tester.getRect(find.byWidgetPredicate(
        (w) => w is ConstrainedBox && w.constraints.maxWidth == 480,
      ));

  testWidgets('desktop web displays the centred sign-in card with every control', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LoginScreen())),
    );
    await tester.pump();

    // Centred card, never wider than 480 px on a wide screen.
    final card = signInCard(tester);
    expect(card.width, lessThanOrEqualTo(480));
    expect(card.center.dx, closeTo(640, 1));

    // Branding, heading and both sign-in modes.
    expect(find.byType(BrandLogo), findsOneWidget);
    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('Sign in with password'), findsOneWidget);
    expect(find.text('Sign in with code (OTP)'), findsOneWidget);
    expect(find.text('Email address'), findsOneWidget);
    expect(find.text('Send sign in code'), findsOneWidget);
    expect(find.text('Create a dealer account'), findsOneWidget);
    expect(find.text('Shop Employee Login'), findsOneWidget);

    // Switching to password mode on desktop.
    await tester.tap(find.text('Sign in with password'));
    await tester.pump();
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
    expect(find.text('Send sign in code'), findsNothing);

    final error = tester.takeException();
    expect(error, isNull);
  });

  testWidgets('tablet displays balanced centered card without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LoginScreen())),
    );
    await tester.pump();

    final card = signInCard(tester);
    expect(card.width, lessThanOrEqualTo(480));
    expect(card.center.dx, closeTo(400, 1));
    expect(card.left, greaterThan(0));
    expect(card.right, lessThan(800));
    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('Send sign in code'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
