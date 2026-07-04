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
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

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

/// Token-refresh interceptor.
///
/// KEY FIX for auto-logout bug:
/// [QueuedInterceptor] serialises [onError] calls, so when 3 tabs all get 401
/// simultaneously, the errors are processed one after another. The original
/// boolean `_isRefreshing` was reset to false *before* the next error started,
/// so every queued 401 independently triggered a fresh /auth/refresh/ call.
/// On rotating-token backends this burnt the session: second refresh used an
/// already-invalidated refresh token → server returned 401/400 → storage was
/// wiped → unexpected logout.
///
/// Fix: before refreshing, compare the token that *caused* the 401 with the
/// token currently in storage. If they differ, a previous queued error already
/// refreshed the token — just retry with the new one, no refresh needed.
class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this._storage, this._dio);
  final FlutterSecureStorage _storage;
  final Dio _dio;

  // Paths that must NOT carry an existing token — a stale/deleted-user token
  // causes the server to reject these with 401 user_not_found before the view
  // even runs, even though they are AllowAny endpoints.
  static const _noAuthPaths = [
    '/auth/login',
    '/auth/register',
    '/auth/refresh',
    '/auth/firebase-token',
    '/auth/verify-otp',
    '/auth/send-otp',
  ];

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final path = options.path;
    final isPublic = _noAuthPaths.any((p) => path.contains(p));
    if (!isPublic) {
      final token = await _storage.read(key: SecureStorageKeys.accessToken);
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
    }
    return handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final path = err.requestOptions.path;
    final isAuth = path.contains('/auth/login') || path.contains('/auth/refresh');

    // Transient "connection closed before full header" — a keep-alive race
    // with the server. No response means nothing was processed, so a single
    // retry is safe. Guard with a flag to avoid loops.
    if (err.response == null && err.requestOptions.extra['retried'] != true) {
      err.requestOptions.extra['retried'] = true;
      try {
        await Future.delayed(const Duration(milliseconds: 300));
        final retry = await _dio.fetch(err.requestOptions);
        return handler.resolve(retry);
      } catch (_) {
        return handler.next(err);
      }
    }

    if (err.response?.statusCode != 401 || isAuth) {
      return handler.next(err);
    }

    // Token that was used when the request FAILED.
    final failedToken = (err.requestOptions.headers['Authorization'] as String?)
        ?.replaceFirst('Bearer ', '');

    // Token currently in storage (may have been refreshed by a previous queued error).
    final storedToken = await _storage.read(key: SecureStorageKeys.accessToken);

    if (storedToken != null && storedToken != failedToken) {
      // Another queued 401 already refreshed the token — just retry.
      err.requestOptions.headers['Authorization'] = 'Bearer $storedToken';
      try {
        final retry = await _dio.fetch(err.requestOptions);
        return handler.resolve(retry);
      } catch (_) {
        return handler.next(err);
      }
    }

    // We are the first to see this expired token — do the refresh.
    try {
      final newAccess = await _doRefresh();
      if (newAccess == null) return handler.next(err);
      err.requestOptions.headers['Authorization'] = 'Bearer $newAccess';
      final retry = await _dio.fetch(err.requestOptions);
      return handler.resolve(retry);
    } catch (_) {
      return handler.next(err);
    }
  }

  /// Calls /auth/refresh/, stores new tokens, returns new access token.
  /// Returns null (and wipes storage) on any failure.
  Future<String?> _doRefresh() async {
    try {
      final refresh = await _storage.read(key: SecureStorageKeys.refreshToken);
      if (refresh == null) {
        await _storage.deleteAll();
        return null;
      }

      final r = await Dio().post(
        '${ApiConstants.baseUrl}${ApiConstants.refresh}',
        data: {'refresh': refresh},
      );

      final newAccess  = r.data['access']  ?? r.data['data']?['access'];
      final newRefresh = r.data['refresh'] ?? r.data['data']?['refresh'];

      if (newAccess == null) {
        await _storage.deleteAll();
        return null;
      }

      await _storage.write(key: SecureStorageKeys.accessToken,  value: newAccess.toString());
      if (newRefresh != null) {
        await _storage.write(key: SecureStorageKeys.refreshToken, value: newRefresh.toString());
      }
      return newAccess.toString();
    } catch (_) {
      await _storage.deleteAll();
      return null;
    }
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
        final raw = body['errors'];
        errors = raw is List ? List<dynamic>.from(raw) : const [];
      }
      // Use handler.reject so the error flows through onError interceptors
      // (allows _AuthInterceptor to retry on 401 before surfacing to the UI).
      return handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
          error: ApiException(
            message: message, errors: errors, statusCode: response.statusCode,
          ),
        ),
        true, // call onError interceptors
      );
    }
    handler.next(response);
  }
}
