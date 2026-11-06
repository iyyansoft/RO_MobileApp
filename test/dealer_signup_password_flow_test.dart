import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ro_wholesale_dealer_app/core/network/api_client.dart';
import 'package:ro_wholesale_dealer_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:ro_wholesale_dealer_app/features/auth/presentation/providers/registration_provider.dart';
import 'package:ro_wholesale_dealer_app/features/auth/presentation/screens/dealer_registration_screen.dart';
import 'package:ro_wholesale_dealer_app/features/auth/presentation/screens/login_screen.dart';
import 'package:ro_wholesale_dealer_app/features/auth/presentation/screens/otp_verification_screen.dart';

void main() {
  testWidgets(
    'create account, verify, reject wrong password, then password sign-in opens Home',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      ApiClient.sessionToken = null;
      addTearDown(() => ApiClient.sessionToken = null);
      Map<String, dynamic>? registered;
      var verified = false;
      final paths = <String>[];
      final api = ApiClient(
        interceptors: [
          InterceptorsWrapper(
            onRequest: (options, handler) {
              paths.add(options.path);
              final body = options.data as Map<String, dynamic>;
              if (options.path == 'auth/signup') {
                expect(body.containsKey('isApproved'), false);
                expect(body['password'], body['confirmPassword']);
                registered = Map.of(body);
                handler.resolve(
                  Response(
                    requestOptions: options,
                    statusCode: 200,
                    data: {'success': true, 'requiresEmailVerification': true},
                  ),
                );
              } else if (options.path == 'auth/send-otp') {
                expect(registered, isNotNull);
                handler.resolve(
                  Response(
                    requestOptions: options,
                    statusCode: 200,
                    data: {'success': true},
                  ),
                );
              } else if (options.path == 'auth/verify-otp') {
                expect(body['otp'], '123456');
                verified = true;
                handler.resolve(
                  Response(
                    requestOptions: options,
                    statusCode: 200,
                    data: {
                      'success': true,
                      'user': {
                        'id': 'test-dealer',
                        'email': registered!['email'],
                        'token': 'test-otp-session',
                      },
                    },
                  ),
                );
              } else if (options.path == 'auth/login') {
                expect(verified, true);
                expect(body['identifier'], registered!['email']);
                if (body['password'] != registered!['password']) {
                  handler.reject(
                    DioException(
                      requestOptions: options,
                      type: DioExceptionType.badResponse,
                      response: Response(
                        requestOptions: options,
                        statusCode: 400,
                        data: {'error': 'Invalid email/mobile or password.'},
                      ),
                    ),
                  );
                } else {
                  handler.resolve(
                    Response(
                      requestOptions: options,
                      statusCode: 200,
                      data: {
                        'success': true,
                        'user': {
                          'id': 'test-dealer',
                          'email': registered!['email'],
                          'status': 'pending',
                          'isApproved': false,
                          'token': 'test-password-session',
                        },
                      },
                    ),
                  );
                }
              } else {
                fail('Unexpected request path: ${options.path}');
              }
            },
          ),
        ],
      );
      final auth = AuthNotifier(api);
      final router = GoRouter(
        initialLocation: '/register',
        routes: [
          GoRoute(
            path: '/register',
            builder: (_, _) => const DealerRegistrationScreen(),
          ),
          GoRoute(
            path: '/otp',
            builder: (_, _) => const OtpVerificationScreen(),
          ),
          GoRoute(
            path: '/login',
            builder: (_, state) => LoginScreen(
              usePassword: state.uri.queryParameters['mode'] == 'password',
            ),
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
          overrides: [
            authProvider.overrideWith((ref) => auth),
            registrationProvider.overrideWith(
              (ref) => RegistrationNotifier(client: api),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> fill(String label, String value) async {
        final field = find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == label,
        );
      await tester.ensureVisible(field);
      await tester.enterText(field, value);
      await tester.pumpAndSettle();
      }

      await fill('Full name', 'Test Dealer');
      await fill('Mobile number', '9876543210');
      await fill('Email address', 'dealer@example.test');
      await fill('Password', 'Test Password 123!');
      await fill('Confirm password', 'Test Password 123!');
    await tester.ensureVisible(find.text('Create account'));
    await tester.pumpAndSettle();
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();
      expect(registered, isNotNull);
      expect(auth.state.isLoggedIn, false);
      expect(find.text('Verify Email'), findsOneWidget);
      for (var i = 0; i < 6; i++) {
        await tester.enterText(find.byType(TextField).at(i), '${i + 1}');
      }
      await tester.ensureVisible(find.text('Verify Email'));
      await tester.tap(find.text('Verify Email'));
      await tester.pumpAndSettle();
      expect(auth.state.isLoggedIn, false);
      expect(ApiClient.sessionToken, isNull);
      expect(find.text('dealer@example.test'), findsOneWidget);
      await fill('Password', 'wrong-password');
      await tester.ensureVisible(find.text('Sign in').last);
      await tester.tap(find.text('Sign in').last);
      await tester.pumpAndSettle();
      expect(auth.state.isLoggedIn, false);
      expect(find.text('Invalid email/mobile or password.'), findsOneWidget);
      await fill('Password', 'Test Password 123!');
      await tester.ensureVisible(find.text('Sign in').last);
      await tester.tap(find.text('Sign in').last);
      await tester.pumpAndSettle();
      expect(find.text('Home Dashboard'), findsOneWidget);
      expect(auth.state.isLoggedIn, true);
      expect(auth.state.currentUser!.isGstVerified, false);
      expect(paths, [
        'auth/signup',
        'auth/send-otp',
        'auth/verify-otp',
        'auth/login',
        'auth/login',
      ]);
      expect(
        await const FlutterSecureStorage().read(key: 'ro_dealer_session'),
        contains('test-password-session'),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
