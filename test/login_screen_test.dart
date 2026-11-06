import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

  testWidgets('desktop web displays two-column layout with left hero panel and right form', (
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

    // Verify left column branding & visual elements
    expect(find.text("India's Premier RO Wholesale Network"), findsOneWidget);
    expect(find.text('B2B PORTAL'), findsOneWidget);
    expect(find.text('Factory-Direct Pricing'), findsOneWidget);
    expect(find.text('100% Tax Compliant GST Billing'), findsOneWidget);
    expect(find.text('Priority Dealer Dispatch'), findsOneWidget);

    // Verify right column login form elements
    expect(find.text('AUTHORIZED DEALER ACCESS'), findsOneWidget);
    expect(find.text('Welcome back, partner'), findsOneWidget);
    expect(find.text('Send sign in code'), findsOneWidget);
    expect(find.text('Create a dealer account'), findsOneWidget);
    expect(find.text('Shop Employee Login'), findsOneWidget);

    // Test switching to password mode on desktop
    await tester.tap(find.text('Sign in with password'));
    await tester.pump();
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);

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

    expect(find.text('Dealer Sign In'), findsOneWidget);
    expect(find.text('Welcome back, partner'), findsOneWidget);
    expect(find.text('Send sign in code'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
