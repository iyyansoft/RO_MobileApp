import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/core/network/api_client.dart';

void main() {
  test('production API default points to the Render backend API root', () {
    expect(ApiClient.defaultBaseUrl, 'https://ro-mobileapp.onrender.com/api/');
    expect(ApiClient().dio.options.baseUrl, ApiClient.defaultBaseUrl);
  });

  test('an explicit development API override remains supported', () {
    const developmentUrl = 'http://10.0.2.2:8080/api/';
    expect(
      ApiClient(baseUrl: developmentUrl).dio.options.baseUrl,
      developmentUrl,
    );
  });

  test('Render cold starts use bounded connection and response timeouts', () {
    final options = ApiClient().dio.options;
    expect(options.connectTimeout, const Duration(seconds: 60));
    expect(options.sendTimeout, const Duration(seconds: 30));
    expect(options.receiveTimeout, const Duration(seconds: 90));
  });

  test(
    'origin build overrides and existing API roots resolve the login route',
    () {
      for (final value in [
        'https://ro-mobileapp.onrender.com',
        'https://ro-mobileapp.onrender.com/',
        'https://ro-mobileapp.onrender.com/api',
        'https://ro-mobileapp.onrender.com/api/',
      ]) {
        final client = ApiClient(baseUrl: value);
        for (final route in [
          'auth/send-otp',
          'auth/verify-otp',
          'auth/login',
          'auth/signup',
          'shop/auth/login',
        ]) {
          expect(
            Uri.parse(client.dio.options.baseUrl).resolve(route).toString(),
            'https://ro-mobileapp.onrender.com/api/$route',
          );
        }
      }
    },
  );
}
