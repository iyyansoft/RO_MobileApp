import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/core/network/api_client.dart';
import 'package:ro_wholesale_dealer_app/features/auth/presentation/providers/auth_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    ApiClient.sessionToken = null;
  });

  test(
    'delivery failure keeps the email and permits retry without signing in',
    () async {
      var requests = 0;
      final api = ApiClient(
        interceptors: [
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requests++;
              expect(options.uri.path, '/api/auth/send-otp');
              expect(options.data, {'email': 'dealer@example.test'});
              expect(options.receiveTimeout, const Duration(seconds: 90));
              if (requests == 1) {
                handler.reject(
                  DioException(
                    requestOptions: options,
                    type: DioExceptionType.badResponse,
                    response: Response(
                      requestOptions: options,
                      statusCode: 502,
                      data: {
                        'error':
                            'Could not send the email code. Please try again.',
                      },
                    ),
                  ),
                );
              } else {
                handler.resolve(
                  Response(
                    requestOptions: options,
                    statusCode: 200,
                    data: {'success': true, 'email': 'dealer@example.test'},
                  ),
                );
              }
            },
          ),
        ],
      );
      final auth = AuthNotifier(api);
      addTearDown(auth.dispose);
      expect(await auth.sendOtp(' Dealer@Example.test '), false);
      expect(auth.state.email, 'dealer@example.test');
      expect(auth.state.canResend, true);
      expect(auth.state.isLoading, false);
      expect(auth.state.isLoggedIn, false);
      expect(auth.state.errorMessage, contains('Could not send'));
      await auth.resendOtp();
      expect(requests, 2);
      expect(auth.state.canResend, false);
      expect(auth.state.errorMessage, isNull);
      expect(auth.state.isLoggedIn, false);
    },
  );

  test('parallel send requests do not send multiple emails', () async {
    var requests = 0;
    final api = ApiClient(
      interceptors: [
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests++;
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {'success': true},
              ),
            );
          },
        ),
      ],
    );
    final auth = AuthNotifier(api);
    addTearDown(auth.dispose);
    final first = auth.sendOtp('dealer@example.test');
    expect(await auth.sendOtp('dealer@example.test'), false);
    expect(await first, true);
    expect(requests, 1);
  });

  test('existing Supabase signup confirmation opens the form without resending or authenticating', () async {
    var requests = 0;
    final api = ApiClient(
      interceptors: [
        InterceptorsWrapper(
          onRequest: (_, _) {
            requests++;
          },
        ),
      ],
    );
    final auth = AuthNotifier(api);
    addTearDown(auth.dispose);
    auth.beginEmailVerification(' Dealer@Example.test ');
    expect(auth.state.email, 'dealer@example.test');
    expect(auth.state.canResend, false);
    expect(auth.state.countdownSeconds, 30);
    expect(auth.state.isLoggedIn, false);
    expect(requests, 0);
    expect(ApiClient.sessionToken, isNull);
  });
}
