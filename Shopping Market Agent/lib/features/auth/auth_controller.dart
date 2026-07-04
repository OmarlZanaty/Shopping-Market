import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/services/notification_service.dart';
import '../../core/storage/secure_storage_keys.dart';
import 'agent_api.dart';

enum AgentRole {
  preparer,
  driver,
  unknown;

  static AgentRole fromString(String? s) {
    switch (s) {
      case 'preparer': return AgentRole.preparer;
      case 'driver':   return AgentRole.driver;
      default:         return AgentRole.unknown;
    }
  }
}

class AgentSession {
  final String? id;
  final String? name;
  final String? phone;
  final AgentRole role;
  final String? branchId;
  final bool isBlocked;

  const AgentSession({
    this.id, this.name, this.phone,
    this.role = AgentRole.unknown,
    this.branchId, this.isBlocked = false,
  });

  bool get isAuthenticated =>
      id != null && (role == AgentRole.preparer || role == AgentRole.driver) && !isBlocked;

  AgentSession copyWith({
    String? id, String? name, String? phone, AgentRole? role,
    String? branchId, bool? isBlocked,
  }) => AgentSession(
        id: id ?? this.id, name: name ?? this.name, phone: phone ?? this.phone,
        role: role ?? this.role, branchId: branchId ?? this.branchId,
        isBlocked: isBlocked ?? this.isBlocked,
      );

  static const empty = AgentSession();
}

class AgentAuthController extends StateNotifier<AsyncValue<AgentSession>> {
  AgentAuthController(this._api) : super(const AsyncValue.loading()) {
    bootstrap();
  }

  final AgentAuthApi _api;
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Called at app start. If a token exists, fetch /me/ to verify (and detect
  /// is_blocked). Otherwise transition to unauthenticated.
  Future<void> bootstrap() async {
    try {
      final token = await _storage.read(key: SecureStorageKeys.accessToken);
      if (token == null) {
        state = const AsyncValue.data(AgentSession.empty);
        return;
      }
      final me = await _api.me();
      final isBlocked = me['is_blocked'] == true || me['is_active'] == false;
      final session = AgentSession(
        id: me['id']?.toString(),
        name: me['full_name']?.toString(),
        phone: me['phone']?.toString(),
        role: AgentRole.fromString(me['role']?.toString()),
        branchId: (me['branch_id'] ?? me['branch'])?.toString(),
        isBlocked: isBlocked,
      );
      state = AsyncValue.data(session);

      // Sync FCM token after bootstrap — use syncTokenAfterAuth() which also
      // handles the case where the token wasn't available at init() time.
      if (!isBlocked) {
        try { await AgentNotificationService.I.syncTokenAfterAuth(); } catch (_) {}
      }
    } catch (e, st) {
      debugPrint('[Auth] bootstrap failed: $e');
      state = const AsyncValue.data(AgentSession.empty);
    }
  }

  Future<void> login(String phone, String password) async {
    state = const AsyncValue.loading();
    try {
      final data = await _api.login(phone, password);
      final user = data['user'] is Map ? Map<String, dynamic>.from(data['user']) : {};
      final role = AgentRole.fromString(user['role']?.toString());
      if (role == AgentRole.unknown) {
        // The login succeeded but this account is not an agent — clean up.
        await _storage.deleteAll();
        throw 'هذا الحساب ليس مخصصاً لعمال التحضير أو التوصيل';
      }
      final session = AgentSession(
        id: user['id']?.toString(),
        name: user['full_name']?.toString(),
        phone: user['phone']?.toString(),
        role: role,
        branchId: (user['branch_id'] ?? user['branch'])?.toString(),
      );
      state = AsyncValue.data(session);

      // Sync FCM token immediately after login.
      try { await AgentNotificationService.I.syncTokenAfterAuth(); } catch (_) {}
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> logout() async {
    await _api.logout();
    state = const AsyncValue.data(AgentSession.empty);
  }
}

final agentAuthApiProvider = Provider<AgentAuthApi>((_) => AgentAuthApi());

final agentAuthControllerProvider =
    StateNotifierProvider<AgentAuthController, AsyncValue<AgentSession>>((ref) {
  return AgentAuthController(ref.read(agentAuthApiProvider));
});
