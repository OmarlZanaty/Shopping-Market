import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/api_constants.dart';
import '../storage/secure_storage_keys.dart';
import 'api_envelope.dart';

class DioClient {
  DioClient._();
  static final DioClient I = DioClient._();
  late final Dio dio;
  final _storage = const FlutterSecureStorage();

  void init() {
    dio = Dio(BaseOptions(
      baseUrl: ApiConstants.baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Accept-Language': 'ar',
      },
      validateStatus: (s) => s != null && s < 500,
    ));

    dio.interceptors.add(_AuthInterceptor(_storage, dio));
    dio.interceptors.add(_ResponseInterceptor());
    if (kDebugMode) {
      dio.interceptors.add(LogInterceptor(
        requestBody: true, responseBody: true,
        logPrint: (o) => debugPrint('[Agent API] $o'),
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
    if (token != null) options.headers['Authorization'] = 'Bearer $token';
    return handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final path = err.requestOptions.path;
    final isAuth = path.contains('/auth/login') || path.contains('/auth/refresh');
    if (err.response?.statusCode == 401 && !isAuth && !_isRefreshing) {
      _isRefreshing = true;
      try {
        final refresh = await _storage.read(key: SecureStorageKeys.refreshToken);
        if (refresh == null) {
          await _storage.deleteAll();
          return handler.next(err);
        }
        final r = await Dio().post(
          '${ApiConstants.baseUrl}${ApiConstants.refresh}',
          data: {'refresh': refresh},
        );
        final newAccess = r.data['access'] ?? r.data['data']?['access'];
        final newRefresh = r.data['refresh'] ?? r.data['data']?['refresh'];
        if (newAccess != null) {
          await _storage.write(key: SecureStorageKeys.accessToken, value: newAccess);
        }
        if (newRefresh != null) {
          await _storage.write(key: SecureStorageKeys.refreshToken, value: newRefresh);
        }
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
    handler.next(err);
  }
}

class _ResponseInterceptor extends Interceptor {
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (response.statusCode != null && response.statusCode! >= 400) {
      final body = response.data;
      String message = 'حدث خطأ';
      List<dynamic> errors = const [];
      if (body is Map) {
        message = (body['message'] ?? body['detail'] ?? message).toString();
        errors = (body['errors'] as List?) ?? const [];
      }
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: ApiException(
          message: message, errors: errors, statusCode: response.statusCode,
        ),
      );
    }
    handler.next(response);
  }
}
