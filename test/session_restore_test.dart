import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/core/network/api_client.dart';
import 'package:ro_wholesale_dealer_app/features/auth/presentation/providers/auth_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('removed dealer sessions cannot restore a cached profile', () async {
    FlutterSecureStorage.setMockInitialValues({
      'ro_dealer_session': jsonEncode({
        'id': 'old',
        'name': 'Old dealer',
        'email': 'old@example.invalid',
        'token': 'old-token',
      }),
    });
    final api = ApiClient(
      interceptors: [
        InterceptorsWrapper(
          onRequest: (request, handler) => handler.reject(
            DioException(
              requestOptions: request,
              response: Response(
                requestOptions: request,
                statusCode: 401,
                data: {'success': false},
              ),
              type: DioExceptionType.badResponse,
            ),
          ),
        ),
      ],
    );
    final auth = AuthNotifier(api);
    addTearDown(auth.dispose);
    await auth.restoreSession();
    expect(auth.state.isLoggedIn, false);
    expect(auth.state.currentUser, isNull);
    expect(ApiClient.sessionToken, isNull);
    expect(
      await const FlutterSecureStorage().read(key: 'ro_dealer_session'),
      isNull,
    );
  });
}
