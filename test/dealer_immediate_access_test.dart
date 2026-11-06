import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ro_wholesale_dealer_app/core/network/api_client.dart';
import 'package:ro_wholesale_dealer_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:ro_wholesale_dealer_app/features/auth/presentation/screens/otp_verification_screen.dart';
import 'package:ro_wholesale_dealer_app/features/auth/presentation/screens/login_screen.dart';

const verifiedDealer = {
  'id': 'dealer-test',
  'name': 'Verified Dealer',
  'email': 'dealer@example.test',
  'status': 'pending',
  'isApproved': false,
  'token': 'local-test-dealer-session',
};

ApiClient client({bool invalidOtp = false}) => ApiClient(
  interceptors: [
    InterceptorsWrapper(
      onRequest: (options, handler) {
        if (invalidOtp) {
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.badResponse,
              response: Response(
                requestOptions: options,
                statusCode: 400,
                data: {
                  'success': false,
                  'error': 'Code is invalid or expired.',
                },
              ),
            ),
          );
        } else {
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {'success': true, 'user': verifiedDealer},
            ),
          );
        }
      },
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    ApiClient.sessionToken = null;
  });
  tearDown(() => ApiClient.sessionToken = null);

  test(
    'password login accepts verified dealer without admin approval',
    () async {
      final auth = AuthNotifier(client());
      addTearDown(auth.dispose);
      expect(
        await auth.loginWithPassword('dealer@example.test', 'test-password'),
        true,
      );
      expect(auth.state.isLoggedIn, true);
      expect(auth.state.currentUser!.status, 'pending');
      expect(auth.state.currentUser!.isGstVerified, false);
      expect(ApiClient.sessionToken, verifiedDealer['token']);
    },
  );

  test(
    'verified pending dealer restores its server-validated session',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'ro_dealer_session': jsonEncode(verifiedDealer),
      });
      final auth = AuthNotifier(client());
      addTearDown(auth.dispose);
      await auth.restoreSession();
      expect(auth.state.isLoggedIn, true);
      expect(auth.state.currentUser!.status, 'pending');
    },
  );

  for (final signup in [true, false]) {
    testWidgets(
      '${signup ? 'signup verification then password login' : 'OTP login'} opens Home',
      (tester) async {
        final auth = AuthNotifier(client());
        await tester.runAsync(() => auth.sendOtp('dealer@example.test'));
        final router = GoRouter(
          initialLocation: signup ? '/otp?flow=signup' : '/otp',
          routes: [
            GoRoute(
              path: '/login',
              builder: (_, state) => LoginScreen(
                usePassword: state.uri.queryParameters['mode'] == 'password',
              ),
            ),
            GoRoute(
              path: '/otp',
              builder: (_, _) => const OtpVerificationScreen(),
            ),
            GoRoute(
              path: '/home',
              builder: (_, _) => const Scaffold(body: Text('Home Dashboard')),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [authProvider.overrideWith((ref) => auth)],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();
        for (var index = 0; index < 6; index++) {
          await tester.enterText(
            find.byType(TextField).at(index),
            '${index + 1}',
          );
        }
        final button = find.text(
          signup ? 'Verify Email' : 'Verify OTP & Enter App',
        );
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        if (signup) {
          expect(auth.state.isLoggedIn, false);
          expect(find.text('Home Dashboard'), findsNothing);
          expect(find.text('dealer@example.test'), findsOneWidget);
          await tester.enterText(
            find.byType(TextFormField).last,
            'test-password',
          );
          await tester.ensureVisible(find.text('Sign in').last);
          await tester.tap(find.text('Sign in').last);
          await tester.pumpAndSettle();
        }
        expect(auth.state.isLoggedIn, true);
        expect(find.text('Home Dashboard'), findsOneWidget);
        expect(auth.state.currentUser!.isGstVerified, false);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  test('invalid verification never creates a local session', () async {
    final auth = AuthNotifier(client(invalidOtp: true));
    addTearDown(auth.dispose);
    await auth.sendOtp('dealer@example.test');
    expect(await auth.verifyOtp('123456'), false);
    expect(auth.state.isLoggedIn, false);
    expect(ApiClient.sessionToken, isNull);
    expect(
      await const FlutterSecureStorage().read(key: 'ro_dealer_session'),
      isNull,
    );
  });
}
