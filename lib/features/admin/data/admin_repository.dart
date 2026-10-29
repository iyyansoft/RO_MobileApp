import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show FunctionException, HttpMethod;

import '../../../core/network/api_client.dart';
import '../../../core/supabase/supabase_config.dart';
import 'supabase_admin_catalog_route.dart';
import 'supabase_admin_dealers_route.dart';
import 'supabase_admin_stats_route.dart';
import 'supabase_admin_dealer_approval_route.dart';
import 'supabase_admin_orders_route.dart';
import 'supabase_admin_analytics_route.dart';
import 'supabase_admin_order_status_route.dart';
import 'supabase_admin_shop_enquiries_route.dart';
import 'supabase_admin_shop_notifications_route.dart';
import 'supabase_admin_shop_employees_route.dart';

/// Admin sessions are separate from dealer sessions and never use demo headers.
class AdminRepository {
  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: ApiClient.defaultBaseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );
  String? token;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<bool> restoreSession() async {
    token = await _storage.read(key: 'ro_admin_token');
    if (token == null) return false;
    final session = await request('session');
    if (SupabaseConfig.adminSupabaseEnabled) {
      await _discardUntrustedSupabaseAdminSession();
    }
    return session['authenticated'] == true;
  }

  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    dynamic data,
  }) async {
    if (SupabaseConfig.adminShopEmployeesSessionActive &&
        isSupabaseAdminShopEmployeesRequest(path, method: method)) {
      return _requestSupabaseAdminShopEmployees();
    }

    if (SupabaseConfig.adminShopNotificationsSessionActive &&
        isSupabaseAdminShopNotificationsRequest(path, method: method)) {
      return _requestSupabaseAdminShopNotifications();
    }

    if (SupabaseConfig.adminShopEnquiriesSessionActive &&
        isSupabaseAdminShopEnquiriesRequest(path, method: method)) {
      return _requestSupabaseAdminShopEnquiries();
    }

    final orderStatusRequest = SupabaseConfig.adminOrderStatusSessionActive
        ? mapSupabaseAdminOrderStatusRequest(path, method: method, data: data)
        : null;
    if (orderStatusRequest != null) {
      return _requestSupabaseAdminOrderStatus(orderStatusRequest);
    }

    if (SupabaseConfig.adminAnalyticsSessionActive &&
        isSupabaseAdminAnalyticsRequest(path, method: method)) {
      return _requestSupabaseAdminAnalytics(supabaseAdminAnalyticsPeriod(path));
    }

    if (SupabaseConfig.adminOrdersSessionActive &&
        isSupabaseAdminOrdersRequest(path, method: method)) {
      return _requestSupabaseAdminOrders();
    }

    if (SupabaseConfig.adminStatsSessionActive &&
        isSupabaseAdminStatsRequest(path, method: method)) {
      return _requestSupabaseAdminStats();
    }

    if (SupabaseConfig.adminDealersSessionActive &&
        isSupabaseAdminDealersRequest(path, method: method)) {
      return _requestSupabaseAdminDealers();
    }

    final dealerApprovalRequest =
        SupabaseConfig.adminDealerApprovalSessionActive
        ? mapSupabaseAdminDealerApprovalRequest(
            path,
            method: method,
            data: data,
          )
        : null;
    if (dealerApprovalRequest != null) {
      return _requestSupabaseAdminDealerApproval(dealerApprovalRequest);
    }

    final supabaseRequest = SupabaseConfig.adminCatalogSessionActive
        ? mapSupabaseAdminCatalogRequest(
            path,
            method: method,
            data: data,
            allowCatalog: SupabaseConfig.adminCatalogEnabled,
            allowBulkImport: SupabaseConfig.adminBulkImportEnabled,
          )
        : null;
    if (supabaseRequest != null) {
      return _requestSupabaseAdminCatalog(supabaseRequest);
    }
    try {
      final response = await _dio.request<dynamic>(
        'admin/$path',
        data: data,
        options: Options(
          method: method,
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
            if (token != null) 'x-admin-token': token,
          },
        ),
      );
      final result = Map<String, dynamic>.from(response.data as Map);
      if (result['success'] != true) {
        throw Exception(result['error'] ?? 'Request failed');
      }
      return result;
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        token = null;
        await _storage.delete(key: 'ro_admin_token');
      }
      final body = error.response?.data;
      throw Exception(
        body is Map
            ? body['error'] ?? 'Request failed'
            : 'Unable to connect to the server. Please retry.',
      );
    }
  }

  Future<void> login(String email, String password) async {
    final result = await request(
      'login',
      method: 'POST',
      data: {'email': email.trim(), 'password': password},
    );
    token = result['token'] as String;
    await _storage.write(key: 'ro_admin_token', value: token);
    await _trySupabaseAdminSignIn(email.trim(), password);
  }

  Future<void> logout() async {
    try {
      await request('logout', method: 'POST');
    } finally {
      if (SupabaseConfig.adminSupabaseEnabled) {
        try {
          await SupabaseConfig.client.auth.signOut();
        } catch (_) {
          // The Express session remains the fallback and is still cleared.
        }
      }
      token = null;
      await _storage.delete(key: 'ro_admin_token');
    }
  }

  Future<Map<String, dynamic>> _requestSupabaseAdminCatalog(
    SupabaseAdminCatalogRequest request,
  ) async {
    try {
      final response = await SupabaseConfig.client.functions.invoke(
        'admin-catalog',
        body: request.toJson(),
      );
      final data = response.data;
      if (data is! Map) throw Exception('Invalid Supabase catalog response.');
      final result = Map<String, dynamic>.from(data);
      if (result['success'] != true) {
        throw Exception(result['error'] ?? 'Catalog request failed.');
      }
      return result;
    } catch (error) {
      // Do not retry a failed Supabase mutation through Express: that could
      // duplicate a request whose database outcome is uncertain.
      if (error is FunctionException) {
        final details = error.details;
        if (details is Map && details['error'] != null) {
          throw Exception(details['error']);
        }
        throw Exception('Supabase catalog request failed (${error.status}).');
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _requestSupabaseAdminDealerApproval(
    SupabaseAdminDealerApprovalRequest request,
  ) async {
    try {
      final response = await SupabaseConfig.client.functions.invoke(
        'admin-dealer-approval',
        body: request.toJson(),
      );
      final data = response.data;
      if (data is! Map) throw Exception('Invalid Supabase dealer response.');
      final result = Map<String, dynamic>.from(data);
      if (result['success'] != true) {
        throw Exception(result['error'] ?? 'Dealer status could not be saved.');
      }
      return result;
    } catch (error) {
      // A status update is never replayed through Express after an uncertain
      // Edge Function response. The administrator can refresh to inspect the
      // saved status before retrying.
      if (error is FunctionException) {
        final details = error.details;
        if (details is Map && details['error'] != null) {
          throw Exception(details['error']);
        }
        throw Exception('Supabase dealer update failed (${error.status}).');
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _requestSupabaseAdminDealers() async {
    try {
      final response = await SupabaseConfig.client.functions.invoke(
        'admin-dealers',
        method: HttpMethod.get,
      );
      final data = response.data;
      if (data is! Map) throw Exception('Invalid Supabase dealer response.');
      final result = Map<String, dynamic>.from(data);
      if (result['success'] != true || result['dealers'] is! List) {
        throw Exception(result['error'] ?? 'Dealer data could not be loaded.');
      }
      return result;
    } catch (error) {
      if (error is FunctionException) {
        final details = error.details;
        if (details is Map && details['error'] != null) {
          throw Exception(details['error']);
        }
        throw Exception('Supabase dealer list failed (${error.status}).');
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _requestSupabaseAdminStats() async {
    try {
      final response = await SupabaseConfig.client.functions.invoke(
        'admin-dashboard-stats',
        method: HttpMethod.get,
      );
      final data = response.data;
      if (data is! Map || data['stats'] is! Map) {
        throw Exception('Invalid Supabase dashboard statistics response.');
      }
      final result = Map<String, dynamic>.from(data);
      if (result['success'] != true) {
        throw Exception(
          result['error'] ?? 'Dashboard statistics could not be loaded.',
        );
      }
      return result;
    } catch (error) {
      if (error is FunctionException) {
        final details = error.details;
        if (details is Map && details['error'] != null) {
          throw Exception(details['error']);
        }
        throw Exception('Supabase dashboard request failed (${error.status}).');
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _requestSupabaseAdminOrders() async {
    try {
      final response = await SupabaseConfig.client.functions.invoke(
        'admin-orders',
        method: HttpMethod.get,
      );
      final data = response.data;
      if (data is! Map || data['orders'] is! List) {
        throw Exception('Invalid Supabase order response.');
      }
      final result = Map<String, dynamic>.from(data);
      if (result['success'] != true) {
        throw Exception(result['error'] ?? 'Order data could not be loaded.');
      }
      return result;
    } catch (error) {
      if (error is FunctionException) {
        final details = error.details;
        if (details is Map && details['error'] != null) {
          throw Exception(details['error']);
        }
        throw Exception('Supabase order list failed (${error.status}).');
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _requestSupabaseAdminShopEnquiries() async {
    try {
      final response = await SupabaseConfig.client.functions.invoke(
        'admin-shop-enquiries',
        method: HttpMethod.get,
      );
      final data = response.data;
      if (data is! Map || data['enquiries'] is! List) {
        throw Exception('Invalid Supabase shop enquiry response.');
      }
      final result = Map<String, dynamic>.from(data);
      if (result['success'] != true) {
        throw Exception(result['error'] ?? 'Shop enquiries are unavailable.');
      }
      return result;
    } catch (error) {
      if (error is FunctionException) {
        final details = error.details;
        if (details is Map && details['error'] != null) {
          throw Exception(details['error']);
        }
        throw Exception(
          'Supabase shop enquiry request failed (${error.status}).',
        );
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _requestSupabaseAdminShopNotifications() async {
    try {
      final response = await SupabaseConfig.client.functions.invoke(
        'admin-shop-notifications',
        method: HttpMethod.get,
      );
      final data = response.data;
      if (data is! Map || data['notifications'] is! List) {
        throw Exception('Invalid Supabase shop notification response.');
      }
      final result = Map<String, dynamic>.from(data);
      if (result['success'] != true) {
        throw Exception(
          result['error'] ?? 'Shop delivery notifications are unavailable.',
        );
      }
      return result;
    } catch (error) {
      if (error is FunctionException) {
        final details = error.details;
        if (details is Map && details['error'] != null) {
          throw Exception(details['error']);
        }
        throw Exception(
          'Supabase shop notification request failed (${error.status}).',
        );
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _requestSupabaseAdminShopEmployees() async {
    try {
      final response = await SupabaseConfig.client.functions.invoke(
        'admin-shop-employees',
        method: HttpMethod.get,
      );
      final data = response.data;
      if (data is! Map || data['employees'] is! List) {
        throw Exception('Invalid Supabase shop employee response.');
      }
      final result = Map<String, dynamic>.from(data);
      if (result['success'] != true) {
        throw Exception(result['error'] ?? 'Employee list is unavailable.');
      }
      return result;
    } catch (error) {
      if (error is FunctionException) {
        final details = error.details;
        if (details is Map && details['error'] != null) {
          throw Exception(details['error']);
        }
        throw Exception(
          'Supabase shop employee request failed (${error.status}).',
        );
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _requestSupabaseAdminAnalytics(
    String period,
  ) async {
    try {
      final response = await SupabaseConfig.client.functions.invoke(
        'admin-analytics',
        method: HttpMethod.get,
        queryParameters: {'period': period},
      );
      final data = response.data;
      if (data is! Map || data['revenue'] is! Map || data['chart'] is! Map) {
        throw Exception('Invalid Supabase analytics response.');
      }
      final result = Map<String, dynamic>.from(data);
      if (result['success'] != true) {
        throw Exception(result['error'] ?? 'Analytics could not be generated.');
      }
      return result;
    } catch (error) {
      if (error is FunctionException) {
        final details = error.details;
        if (details is Map && details['error'] != null) {
          throw Exception(details['error']);
        }
        throw Exception('Supabase analytics failed (${error.status}).');
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _requestSupabaseAdminOrderStatus(
    SupabaseAdminOrderStatusRequest request,
  ) async {
    try {
      final response = await SupabaseConfig.client.functions.invoke(
        'admin-order-status',
        body: request.toJson(),
      );
      final data = response.data;
      if (data is! Map || data['success'] != true) {
        throw Exception(
          data is Map
              ? data['error'] ?? 'Order status could not be saved.'
              : 'Invalid Supabase order status response.',
        );
      }
      return Map<String, dynamic>.from(data);
    } catch (error) {
      // Do not replay a status mutation through Express when a Supabase
      // response is uncertain; refresh the order before an explicit retry.
      if (error is FunctionException) {
        final details = error.details;
        if (details is Map && details['error'] != null) {
          throw Exception(details['error']);
        }
        throw Exception('Supabase order status failed (${error.status}).');
      }
      rethrow;
    }
  }

  Future<void> _trySupabaseAdminSignIn(String email, String password) async {
    if (!SupabaseConfig.adminSupabaseEnabled) return;
    try {
      final result = await SupabaseConfig.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      final user = result.user;
      if (user == null ||
          user.emailConfirmedAt == null ||
          user.appMetadata['role'] != 'admin') {
        await SupabaseConfig.client.auth.signOut();
      }
    } catch (_) {
      // Existing Express admin login remains authoritative unless a separately
      // provisioned Supabase Auth admin session is available for catalog CRUD.
      try {
        await SupabaseConfig.client.auth.signOut();
      } catch (_) {}
    }
  }

  Future<void> _discardUntrustedSupabaseAdminSession() async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null ||
        user.emailConfirmedAt == null ||
        user.appMetadata['role'] != 'admin') {
      await SupabaseConfig.client.auth.signOut();
    }
  }
}
