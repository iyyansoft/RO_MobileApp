import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/core/widgets/brand_logo.dart';
import 'package:ro_wholesale_dealer_app/features/auth/presentation/screens/login_screen.dart';

void main() {
  testWidgets('LoginScreen renders modern centered white login card on desktop without promotional panel', (tester) async {
    // Set desktop screen size: 1200 x 800
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: LoginScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Verify Top Brand Logo is present
    expect(find.byType(BrandLogo), findsOneWidget);

    // 2. Verify promotional left panel is removed completely
    expect(find.text("India's Premier\nRO Wholesale Network"), findsNothing);
    expect(find.text('B2B PORTAL'), findsNothing);
    expect(find.text('Factory-Direct Pricing'), findsNothing);
    expect(find.text('100% Tax Compliant GST Billing'), findsNothing);
    expect(find.text('Priority Dealer Dispatch'), findsNothing);

    // 3. Verify Login Card Form Elements
    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('Sign in with password'), findsOneWidget);
    expect(find.text('Sign in with code (OTP)'), findsOneWidget);
    expect(find.text('Create a dealer account'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
    expect(find.text('Shop Employee Login'), findsOneWidget);
  });

  testWidgets('LoginScreen renders clean mobile centered layout without overflow', (tester) async {
    // Set mobile screen size: 390 x 844
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: LoginScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Mobile form elements
    expect(find.byType(BrandLogo), findsOneWidget);
    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('Sign in with password'), findsOneWidget);
    expect(find.text('Sign in with code (OTP)'), findsOneWidget);
    expect(find.text('Create a dealer account'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
    expect(find.text('Shop Employee Login'), findsOneWidget);
  });
}
