import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/core/network/api_client.dart';
import 'package:ro_wholesale_dealer_app/features/shop/data/shop_employee_repository.dart';

void main() {
  test(
    'employee login posts to the API route and preserves validation errors',
    () async {
      final dio = Dio(BaseOptions(baseUrl: ApiClient.defaultBaseUrl));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.method, 'POST');
            expect(
              options.uri.toString(),
              'https://ro-mobileapp.onrender.com/api/shop/auth/login',
            );
            expect(options.data, {
              'loginId': 'EMP001',
              'password': 'test-only',
            });
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.badResponse,
                response: Response(
                  requestOptions: options,
                  statusCode: 400,
                  data: {
                    'success': false,
                    'error': 'Enter your Login ID and password.',
                  },
                ),
              ),
            );
          },
        ),
      );
      await expectLater(
        ShopEmployeeRepository.forTesting(dio).login(' EMP001 ', 'test-only'),
        throwsA(
          predicate(
            (e) => e.toString().contains('Enter your Login ID and password.'),
          ),
        ),
      );
    },
  );

  for (final scenario in ['html', 'timeout', 'notFound', 'success']) {
    test('employee request handles $scenario', () async {
      final dio = Dio(BaseOptions(baseUrl: ApiClient.defaultBaseUrl));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (scenario == 'timeout' || scenario == 'notFound') {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: scenario == 'timeout'
                      ? DioExceptionType.receiveTimeout
                      : DioExceptionType.badResponse,
                  response: scenario == 'notFound'
                      ? Response(
                          requestOptions: options,
                          statusCode: 404,
                          data: '<html>Not found</html>',
                        )
                      : null,
                ),
              );
            } else {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: scenario == 'html'
                      ? '<html></html>'
                      : {'success': true},
                ),
              );
            }
          },
        ),
      );
      final request = ShopEmployeeRepository.forTesting(dio)
          .request('shop/auth/login');
      if (scenario == 'success') {
        expect(await request, {'success': true});
      } else {
        final message = {
          'html': 'invalid response',
          'timeout': 'timed out',
          'notFound': 'HTTP 404',
        }[scenario]!;
        await expectLater(
          request,
          throwsA(predicate((e) => e.toString().contains(message))),
        );
      }
    });
  }
}
