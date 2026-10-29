import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../../core/network/api_client.dart';

class ShopEmployeeRepository {
  ShopEmployeeRepository._();
  static final ShopEmployeeRepository instance = ShopEmployeeRepository._();
  static const _storage = FlutterSecureStorage();
  static const _key = 'ro_shop_employee_token';
  String? token;
  Map<String, dynamic>? employee;

  /// Builds the explicit per-order-item delivery status contract expected by
  /// the shop API. `deliveryConfirmed` is retained for the current route while
  /// `deliveryStatus` supports API validators that consume a status string.
  static List<Map<String, Object>> buildDeliveryItemsPayload(
    Map<int, int> quantities,
    Set<int> confirmedItems,
  ) => quantities.entries.map((item) {
    final confirmed = confirmedItems.contains(item.key);
    return <String, Object>{
      'orderItemId': item.key,
      'deliveredQuantity': item.value,
      'deliveryConfirmed': confirmed,
      'deliveryStatus': confirmed ? 'delivered' : 'not_delivered',
      // Keep compatibility with the existing route's legacy boolean alias.
      'delivered': confirmed,
    };
  }).toList();

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: ApiClient.defaultBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 25),
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ),
  );

  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Object? data,
    Map<String, dynamic>? query,
  }) async {
    try {
      final response = await _dio.request<dynamic>(
        path,
        data: data,
        queryParameters: query,
        options: Options(
          method: method,
          headers: {if (token != null) 'Authorization': 'Bearer $token'},
        ),
      );
      final result = Map<String, dynamic>.from(response.data as Map);
      if (result['success'] != true) {
        throw Exception(result['error'] ?? 'Request failed.');
      }
      return result;
    } on DioException catch (error) {
      final data = error.response?.data;
      if (error.response?.statusCode == 401) await logout();
      throw Exception(
        data is Map
            ? data['error'] ?? 'Unable to connect to the server.'
            : 'Unable to connect to the server.',
      );
    }
  }

  Future<void> restore() async {
    token = await _storage.read(key: _key);
    if (token == null) return;
    try {
      final result = await request('shop/auth/session');
      employee = Map<String, dynamic>.from(result['employee'] as Map);
    } catch (_) {
      token = null;
      employee = null;
      await _storage.delete(key: _key);
    }
  }

  Future<void> login(String loginId, String password) async {
    final result = await request(
      'shop/auth/login',
      method: 'POST',
      data: {'loginId': loginId.trim(), 'password': password},
    );
    token = '${result['token']}';
    employee = Map<String, dynamic>.from(result['employee'] as Map);
    await _storage.write(key: _key, value: token);
  }

  Future<void> logout() async {
    token = null;
    employee = null;
    await _storage.delete(key: _key);
  }
}
