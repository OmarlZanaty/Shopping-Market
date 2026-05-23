import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/constants/api_constants.dart';
import '../../core/network/api_envelope.dart';
import '../../core/network/dio_client.dart';
import '../../core/storage/secure_storage_keys.dart';

/// Auth-specific API surface for the agent app.
class AgentAuthApi {
  AgentAuthApi();
  Dio get _dio => DioClient.I.dio;
  final _storage = const FlutterSecureStorage();

  /// Login with phone + password. Returns the user payload.
  Future<Map<String, dynamic>> login(String phone, String password) async {
    final res = await _dio.post(ApiConstants.login, data: {
      'phone': phone, 'password': password,
    });
    final body = ApiEnvelope.unwrap(res.data) ?? res.data;
    if (body is Map) {
      final m = Map<String, dynamic>.from(body);
      final access = m['access'];
      final refresh = m['refresh'];
      if (access != null) {
        await _storage.write(key: SecureStorageKeys.accessToken, value: access);
      }
      if (refresh != null) {
        await _storage.write(key: SecureStorageKeys.refreshToken, value: refresh);
      }
      final user = m['user'];
      if (user is Map) {
        await _storage.write(key: SecureStorageKeys.role, value: user['role']?.toString());
        await _storage.write(key: SecureStorageKeys.agentId, value: user['id']?.toString());
        await _storage.write(key: SecureStorageKeys.agentName, value: user['full_name']?.toString());
        await _storage.write(key: SecureStorageKeys.agentPhone, value: user['phone']?.toString());
        final branchId = user['branch_id'] ?? user['branch'];
        if (branchId != null) {
          await _storage.write(key: SecureStorageKeys.branchId, value: branchId.toString());
        }
      }
      return m;
    }
    return {};
  }

  /// Returns the current user profile. Used at app start to detect a blocked
  /// account (force logout) and to refresh stored role.
  Future<Map<String, dynamic>> me() async {
    final res = await _dio.get(ApiConstants.me);
    final body = ApiEnvelope.unwrap(res.data) ?? res.data;
    return Map<String, dynamic>.from(body is Map ? body : {});
  }

  Future<void> sendFcmToken(String token) async {
    await _dio.post(ApiConstants.fcmToken, data: {'fcm_token': token});
  }

  Future<void> logout() async {
    try {
      final refresh = await _storage.read(key: SecureStorageKeys.refreshToken);
      await _dio.post(ApiConstants.logout, data: {'refresh': refresh});
    } catch (_) {}
    await _storage.deleteAll();
  }
}
