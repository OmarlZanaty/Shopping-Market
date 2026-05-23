import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/api_constants.dart';
import '../storage/secure_storage_keys.dart';
import 'api_envelope.dart';

/// Centralised Dio client with auth + refresh + error interceptors.
///
/// All ApiService methods funnel through this. Adds:
/// - Authorization: Bearer <access> on every request
/// - 401 → refresh → retry
/// - Errors parsed into ApiException
/// - Request logging in debug
class DioClient {
  DioClient._();
  static final DioClient _instance = DioClient._();
  factory DioClient() => _instance;

  late final Dio dio;
  final _storage = const FlutterSecureStorage();

  void init() {
    dio = Dio(BaseOptions(
      baseUrl: ApiConstants.baseUrl,
      connectTimeout: ApiConstants.connectTimeout,
      receiveTimeout: ApiConstants.receiveTimeout,
      sendTimeout: ApiConstants.connectTimeout,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Accept-Language': 'ar',
      },
      validateStatus: (status) => status != null && status < 500,
    ));

    dio.interceptors.add(_AuthInterceptor(_storage, dio));
    dio.interceptors.add(_ErrorInterceptor());
    if (kDebugMode) {
      dio.interceptors.add(LogInterceptor(
        requestBody: true,
        responseBody: true,
        logPrint: (obj) => debugPrint('[API] $obj'),
      ));
    }
  }
}

class _AuthInterceptor extends QueuedInterceptor {
  _AuthInterceptor(this._storage, this._dio);
  final FlutterSecureStorage _storage;
  final Dio _dio;
  bool _isRefreshing = false;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _storage.read(key: SecureStorageKeys.accessToken);
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    return handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final path = err.requestOptions.path;
    final isAuthEndpoint = path.contains('/auth/login') ||
        path.contains('/auth/send-otp') ||
        path.contains('/auth/verify-otp') ||
        path.contains('/auth/refresh') ||
        path.contains('/auth/social');

    if (err.response?.statusCode == 401 && !isAuthEndpoint && !_isRefreshing) {
      _isRefreshing = true;
      try {
        final refresh = await _storage.read(key: SecureStorageKeys.refreshToken);
        if (refresh == null) {
          await _storage.deleteAll();
          return handler.next(err);
        }
        final res = await Dio().post(
          '${ApiConstants.baseUrl}${ApiConstants.authRefresh}',
          data: {'refresh': refresh},
          options: Options(headers: {'Content-Type': 'application/json'}),
        );
        final newAccess = res.data['access'] ?? res.data['data']?['access'];
        final newRefresh = res.data['refresh'] ?? res.data['data']?['refresh'];
        if (newAccess != null) {
          await _storage.write(key: SecureStorageKeys.accessToken, value: newAccess);
        }
        if (newRefresh != null) {
          await _storage.write(key: SecureStorageKeys.refreshToken, value: newRefresh);
        }
        // Retry original request with new token
        err.requestOptions.headers['Authorization'] = 'Bearer $newAccess';
        final retry = await _dio.fetch(err.requestOptions);
        _isRefreshing = false;
        return handler.resolve(retry);
      } catch (_) {
        _isRefreshing = false;
        await _storage.deleteAll();
        return handler.next(err);
      }
    }
    return handler.next(err);
  }
}

class _ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    String message = 'حدث خطأ ما';
    List<dynamic> errors = const [];

    final body = err.response?.data;
    if (body is Map) {
      message = (body['message'] ?? body['detail'] ?? message).toString();
      errors = (body['errors'] as List?) ?? const [];
    }

    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout) {
      message = 'انتهت مهلة الاتصال — تحقق من الإنترنت';
    } else if (err.type == DioExceptionType.connectionError) {
      message = 'لا يوجد اتصال بالإنترنت';
    }

    final wrapped = DioException(
      requestOptions: err.requestOptions,
      response: err.response,
      type: err.type,
      error: ApiException(
        message: message,
        errors: errors,
        statusCode: err.response?.statusCode,
      ),
      message: message,
    );
    handler.next(wrapped);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    // For 4xx responses that arrived via validateStatus<500, raise an exception
    // shape consistent with the envelope.
    if (response.statusCode != null && response.statusCode! >= 400) {
      final body = response.data;
      String message = 'Request failed';
      List<dynamic> errors = const [];
      if (body is Map) {
        message = (body['message'] ?? body['detail'] ?? message).toString();
        errors = (body['errors'] as List?) ?? const [];
      }
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: ApiException(
          message: message,
          errors: errors,
          statusCode: response.statusCode,
        ),
      );
    }
    handler.next(response);
  }
}
