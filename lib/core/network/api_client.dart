import 'package:dio/dio.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic responseData;

  ApiException({
    required this.message,
    this.statusCode,
    this.responseData,
  });

  @override
  String toString() => 'ApiException: $message (Status: $statusCode)';
}

class ApiClient {
  final Dio _dio;

  // Deployed Railway Production Backend Base URL Configuration
  // Supports --dart-define=API_BASE_URL=http://127.0.0.1:8080/api/ for local testing
  static String get defaultBaseUrl {
    return const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://romobileapp-production.up.railway.app/api/',
    );
  }

  ApiClient({
    String? baseUrl,
    List<Interceptor>? interceptors,
  }) : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl ?? defaultBaseUrl,
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 15),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
          ),
        ) {
    if (interceptors != null && interceptors.isNotEmpty) {
      _dio.interceptors.addAll(interceptors);
    } else {
      // Default logging and placeholder auth interceptor
      _dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            // In a real app, retrieve the token from a local storage secure storage provider.
            const dummyToken = 'RO_WHOLESALE_DEMO_TOKEN';
            options.headers['Authorization'] = 'Bearer $dummyToken';
            return handler.next(options);
          },
          onError: (DioException e, handler) {
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

  // GET request wrapper
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    try {
      return await _dio.get<T>(
        path,
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
        path,
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
        path,
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
        path,
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
        message = 'Connection timed out. Please check your internet connection.';
        break;
      case DioExceptionType.badResponse:
        message = _extractErrorMessage(e.response?.data) ?? 'Received invalid response from server.';
        break;
      case DioExceptionType.cancel:
        message = 'Request was cancelled.';
        break;
      case DioExceptionType.connectionError:
        message = 'Could not connect to server. Please check your internet connection.';
        break;
      default:
        message = 'A network error occurred: ${e.message}';
    }

    return ApiException(
      message: message,
      statusCode: statusCode,
      responseData: responseData,
    );
  }

  static String? _extractErrorMessage(dynamic data) {
    if (data is Map<String, dynamic>) {
      if (data.containsKey('message')) {
        return data['message'] as String;
      }
      if (data.containsKey('error')) {
        final error = data['error'];
        if (error is String) return error;
        if (error is Map<String, dynamic> && error.containsKey('message')) {
          return error['message'] as String;
        }
      }
    }
    return null;
  }
}
