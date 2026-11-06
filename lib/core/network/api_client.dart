import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic responseData;

  ApiException({required this.message, this.statusCode, this.responseData});

  @override
  String toString() => 'ApiException: $message (Status: $statusCode)';
}

class ApiClient {
  static String? sessionToken;
  final Dio _dio;

  // The API URL can be overridden at build time with --dart-define=API_BASE_URL=...
  static String get defaultBaseUrl {
    const configured = String.fromEnvironment('API_BASE_URL');
    if (configured.isNotEmpty) {
      return normalizeBaseUrl(configured);
    }
    if (kIsWeb) {
      // In web browser, use the current origin proxy if running locally to avoid
      // browser CORS blocks and port mismatches (8080, 8085, etc.).
      try {
        final origin = Uri.base.origin;
        if (origin.contains('localhost') || origin.contains('127.0.0.1')) {
          return '$origin/api/';
        }
      } catch (_) {
        // Fall back to production backend if Uri.base cannot be accessed
      }
    }
    return normalizeBaseUrl('https://ro-mobileapp.onrender.com');
  }

  /// URL of a file in assets/images/ served by server.js at /images/<file>,
  /// on the same server as the API (e.g. http://localhost:8080 when local).
  static String imageUrl(String fileName) =>
      '${Uri.parse(defaultBaseUrl).origin}/images/$fileName';

  /// Callers use paths relative to /api/, including when the build supplies
  /// only the server origin. Preserve overrides that already contain /api/.
  static String normalizeBaseUrl(String value) {
    final uri = Uri.parse(value.trim());
    final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    return uri
        .replace(path: '${path.endsWith('/api') ? path : '$path/api'}/')
        .toString();
  }

  ApiClient({String? baseUrl, List<Interceptor>? interceptors})
    : _dio = Dio(
        BaseOptions(
          baseUrl: baseUrl == null ? defaultBaseUrl : normalizeBaseUrl(baseUrl),
          connectTimeout: const Duration(seconds: 60),
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 90),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ),
      ) {
    final endpoint = Uri.parse(_dio.options.baseUrl);
    // Only the origin and API path: no credentials, query values or headers.
    debugPrint('[API] base=${endpoint.origin}${endpoint.path}');
    if (interceptors != null && interceptors.isNotEmpty) {
      _dio.interceptors.addAll(interceptors);
    } else {
      // Attach the active dealer token without logging credentials.
      _dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final token = sessionToken;
            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
            }
            return handler.next(options);
          },
          onError: (DioException e, handler) {
            debugPrint(
              '[API] method=${e.requestOptions.method} '
              'path=${e.requestOptions.uri.path} '
              'status=${e.response?.statusCode ?? '-'} type=${e.type.name}',
            );
            if (kDebugMode &&
                e.requestOptions.uri.path == '/api/auth/login' &&
                e.response?.data is Map) {
              final body = e.response!.data as Map;
              debugPrint(
                '[DEALER LOGIN] status=${e.response!.statusCode} '
                'error=${body['error']} accountStatus=${body['status']} '
                'isApproved=${body['isApproved']}',
              );
            }
            final exception = _handleDioException(e);
            return handler.next(
              DioException(
                requestOptions: e.requestOptions,
                response: e.response,
                type: e.type,
                error: exception,
              ),
            );
          },
        ),
      );
    }
  }

  Dio get dio => _dio;

  /// Strips leading slashes or duplicate 'api/' so that callers passing
  /// 'products', '/products', 'api/products', or '/api/products' all resolve
  /// cleanly against the base URL.
  static String cleanPath(String path) {
    var p = path.trim();
    if (p.startsWith('/')) p = p.substring(1);
    if (p.startsWith('api/')) p = p.substring(4);
    return p;
  }

  // GET request wrapper
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    try {
      return await _dio.get<T>(
        cleanPath(path),
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      throw _handleDioException(e);
    }
  }

  // POST request wrapper
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    try {
      return await _dio.post<T>(
        cleanPath(path),
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      throw _handleDioException(e);
    }
  }

  // PUT request wrapper
  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    try {
      return await _dio.put<T>(
        cleanPath(path),
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      throw _handleDioException(e);
    }
  }

  // DELETE request wrapper
  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    try {
      return await _dio.delete<T>(
        cleanPath(path),
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      throw _handleDioException(e);
    }
  }

  static ApiException _handleDioException(DioException e) {
    if (e.error is ApiException) {
      return e.error as ApiException;
    }

    String message = 'An unexpected network error occurred.';
    int? statusCode = e.response?.statusCode;
    dynamic responseData = e.response?.data;

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        message =
            'Connection timed out. Please check your internet connection.';
        break;
      case DioExceptionType.badResponse:
        message =
            _extractErrorMessage(e.response?.data) ??
            (statusCode != null
                ? 'Server returned error status $statusCode.'
                : 'Received invalid response from server.');
        break;
      case DioExceptionType.cancel:
        message = 'Request was cancelled.';
        break;
      case DioExceptionType.connectionError:
        message =
            _extractErrorMessage(e.response?.data) ??
            'Could not connect to server. Please check your internet connection.';
        break;
      case DioExceptionType.badCertificate:
        message = 'Could not verify the server security certificate.';
        break;
      default:
        // Dio messages may contain URLs or internal details.
        message = _extractErrorMessage(e.response?.data) ??
            'An unexpected network error occurred. Please try again.';
    }

    return ApiException(
      message: message,
      statusCode: statusCode,
      responseData: responseData,
    );
  }

  static String? _extractErrorMessage(dynamic data) {
    if (data == null) return null;
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) {
          return _extractFromMap(decoded);
        }
      } catch (_) {
        if (data.trim().isNotEmpty &&
            data.length < 250 &&
            !data.startsWith('<')) {
          return data.trim();
        }
      }
    } else if (data is Map) {
      return _extractFromMap(data);
    }
    return null;
  }

  static String? _extractFromMap(Map data) {
    if (data['error'] is String && (data['error'] as String).trim().isNotEmpty) {
      return (data['error'] as String).trim();
    }
    if (data['message'] is String &&
        (data['message'] as String).trim().isNotEmpty) {
      return (data['message'] as String).trim();
    }
    if (data['error'] is Map) {
      final sub = data['error'] as Map;
      if (sub['message'] is String &&
          (sub['message'] as String).trim().isNotEmpty) {
        return (sub['message'] as String).trim();
      }
    }
    return null;
  }
}
