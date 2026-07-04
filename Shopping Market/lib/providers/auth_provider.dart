import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../utils/constants.dart';

enum AuthStatus { unknown, authenticated, unauthenticated, guest }

/// Outcome of a social (Google/Facebook) login attempt.
/// [needsPhone] means the backend recognised a new account and requires a phone
/// number before it can create the user — the UI should prompt and retry.
enum SocialLoginResult { success, needsPhone, failed }

class AuthProvider extends ChangeNotifier {
  final _api = ApiService();
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  final _localAuth = LocalAuthentication();

  AuthStatus _status = AuthStatus.unknown;
  UserModel? _user;
  bool _isLoading = false;
  String? _error;

  AuthStatus get status => _status;
  UserModel? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isGuest => _status == AuthStatus.guest;
  bool get isCustomer => _user?.isCustomer ?? false;
  bool get isDriver => _user?.isDriver ?? false;

  /// Allows the user to browse the app without logging in.
  /// Protected routes (cart checkout, orders, profile) will redirect to login.
  void browseAsGuest() {
    _status = AuthStatus.guest;
    notifyListeners();
  }

  Future<void> init() async {
    // Register the global unauthorized callback so the API layer can trigger
    // a logout when the refresh token also dies (e.g. rotated + blacklisted).
    ApiService.onUnauthorized = () {
      _user = null;
      _status = AuthStatus.unauthenticated;
      notifyListeners();
    };

    String? token;
    try {
      token = await _storage.read(key: StorageKeys.accessToken);
    } catch (_) {
      // Corrupt secure storage (e.g. reinstall / keystore change) — wipe and
      // start fresh so the user can log in again cleanly.
      await _storage.deleteAll();
    }

    if (token != null) {
      try {
        // Happy path: fetch fresh profile from the server.
        _user = await _api.getProfile();
        _status = AuthStatus.authenticated;
        // Persist the refreshed user data for offline fallback.
        await _storage.write(
          key: StorageKeys.userData,
          value: jsonEncode(_user!.toJson()),
        );
        _pushFcmToken();
      } on DioException catch (e) {
        // ── 401 / 403: token is genuinely invalid → log out. ──────────────
        final code = e.response?.statusCode;
        if (code == 401 || code == 403) {
          _status = AuthStatus.unauthenticated;
        } else {
          // Network error, server 5xx, timeout, etc.
          // Keep the user logged in using cached data — don't punish them for
          // a temporary connectivity issue on startup.
          _status = await _restoreFromCache();
        }
      } catch (_) {
        // Any other unexpected error — try cached data before giving up.
        _status = await _restoreFromCache();
      }
    } else {
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  /// Attempts to restore [_user] from locally cached JSON.
  /// Returns [AuthStatus.authenticated] on success, [AuthStatus.unauthenticated]
  /// if the cache is absent or corrupt.
  Future<AuthStatus> _restoreFromCache() async {
    try {
      final cached = await _storage.read(key: StorageKeys.userData);
      if (cached == null || cached.isEmpty) return AuthStatus.unauthenticated;
      _user = UserModel.fromJson(jsonDecode(cached) as Map<String, dynamic>);
      return AuthStatus.authenticated;
    } catch (_) {
      return AuthStatus.unauthenticated;
    }
  }

  Future<bool> login(String phone, String password) async {
    _setLoading(true);
    try {
      final data = await _api.login(phone, password);

      _user = UserModel.fromJson(data['user']);
      await _storage.write(key: StorageKeys.userData, value: jsonEncode(data['user']));
      _status = AuthStatus.authenticated;
      _error = null;
      notifyListeners();
      _pushFcmToken();
      return true;
    } catch (e) {
      _error = _parseError(e);
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> register({
    required String phone,
    required String fullName,
    required String password,
    String? email,
  }) async {
    _setLoading(true);
    try {
      final data = await _api.register({
        'phone': phone,
        'full_name': fullName,
        'password': password,
        'confirm_password': password,
        if (email != null) 'email': email,
      });
      _user = UserModel.fromJson(data['user']);
      _status = AuthStatus.authenticated;
      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = _parseError(e);
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // ─── Biometric ──────────────────────────────────────────────────────────
  Future<bool> get isBiometricAvailable async {
    final available = await _localAuth.canCheckBiometrics;
    final enrolled = await _localAuth.isDeviceSupported();
    return available && enrolled;
  }

  Future<bool> authenticateWithBiometric() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Use fingerprint to login',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> loginWithBiometric() async {
    _setLoading(true);
    try {
      final authenticated = await authenticateWithBiometric();
      if (!authenticated) {
        _error = 'Biometric authentication failed';
        return false;
      }
      final token = await _storage.read(key: StorageKeys.biometricToken);
      if (token == null) {
        _error = 'Biometric not registered';
        return false;
      }
      final data = await _api.biometricLogin(token);
      _user = UserModel.fromJson(data['user']);
      _status = AuthStatus.authenticated;
      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = _parseError(e);
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> registerBiometric() async {
    try {
      final authenticated = await authenticateWithBiometric();
      if (!authenticated) return false;
      // Generate a unique token for this device
      final token = '${_user!.id}_${DateTime.now().millisecondsSinceEpoch}';
      await _api.registerBiometric(token);
      await _storage.write(key: StorageKeys.biometricToken, value: token);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ─── Social Login ────────────────────────────────────────────────────────
  Future<bool> loginWithGoogle() async {
    _setLoading(true);
    try {
      // Google sign-in handled in the screen, this receives the result
      // See auth_screen.dart for the actual Google sign-in call
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<SocialLoginResult> handleSocialLogin({
    required String provider,
    required String socialId,
    String? phone,
    String? fullName,
    String? email,
  }) async {
    _setLoading(true);
    try {
      final data = await _api.socialLogin(provider, socialId,
          phone: phone, fullName: fullName, email: email);
      _user = data['user'] is Map
          ? UserModel.fromJson(Map<String, dynamic>.from(data['user'] as Map))
          : await _api.getProfile();
      _status = AuthStatus.authenticated;
      _error = null;
      notifyListeners();
      // Persist + push FCM, same as the OTP/biometric paths.
      try {
        await _storage.write(
          key: StorageKeys.userData,
          value: jsonEncode(_user!.toJson()),
        );
      } catch (_) {}
      _pushFcmToken();
      return SocialLoginResult.success;
    } on SocialNeedsPhoneException {
      // New account — caller must collect a phone number and retry.
      return SocialLoginResult.needsPhone;
    } catch (e) {
      _error = _parseError(e);
      notifyListeners();
      return SocialLoginResult.failed;
    } finally {
      _setLoading(false);
    }
  }

  /// Called after Firebase OTP login — sets auth state without a full API round-trip.
  /// Also persists the user to secure storage so the next cold-start can restore
  /// the session from cache if the network is unavailable.
  Future<void> setAuthenticated(UserModel user) async {
    _user = user;
    _status = AuthStatus.authenticated;
    _error = null;
    notifyListeners();
    // Persist for offline fallback — must be valid JSON (not Map.toString()).
    try {
      await _storage.write(
        key: StorageKeys.userData,
        value: jsonEncode(user.toJson()),
      );
    } catch (_) {} // storage failure must never break the login flow
    _pushFcmToken();
  }

  Future<void> updateFcmToken(String token) async {
    try {
      await _api.updateFcmToken(token);
    } catch (_) {}
  }

  /// Grabs the current FCM token from Firebase and registers it with the backend.
  /// Called after every successful login/init so the server always has a fresh token.
  Future<void> _pushFcmToken() async {
    try {
      final token = await NotificationService().fcmToken;
      if (token != null) await _api.updateFcmToken(token);
    } catch (_) {}
  }

  Future<bool> updateProfile({
    required String fullName,
    required String phone,
  }) async {
    _setLoading(true);
    try {
      final updated = await _api.updateProfile(fullName: fullName, phone: phone);
      _user = updated;
      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = _parseError(e);
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Logs the user out.
  ///
  /// Order matters: flip local state FIRST, then notify the router so it
  /// redirects to /login immediately, THEN fire the server-side
  /// `/auth/logout/` call in the background. This avoids the blank-screen
  /// race we used to hit when:
  ///   • the network was slow (UI froze on profile waiting for the response),
  ///   • the access token was already expired (the API call triggered a
  ///     refresh → 401 → onUnauthorized cycle while logout() was mid-flight).
  Future<void> logout() async {
    // 1) Flip auth state synchronously so the router redirect runs first.
    _user = null;
    _status = AuthStatus.unauthenticated;
    _error = null;
    notifyListeners();

    // 2) Fire the API call in the background; swallow any errors. The local
    //    tokens get wiped inside _api.logout() regardless of network result.
    // ignore: unawaited_futures
    _api.logout().catchError((_) {});
  }

  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }

  String _parseError(dynamic e) {
    // The backend sends a ready-to-display message (often Arabic, e.g. the
    // duplicate-phone error from social login) — show it verbatim when present
    // instead of falling back to a generic string.
    if (e is DioException) {
      final body = e.response?.data;
      if (body is Map && body['message'] != null) {
        final serverMsg = body['message'].toString().trim();
        if (serverMsg.isNotEmpty) return serverMsg;
      }
    }

    final msg = e.toString().toLowerCase();

    // Dio 401 or any unauthorized response
    if (msg.contains('401') || msg.contains('unauthorized')) {
      return 'Invalid credentials';
    }
    if (msg.contains('non_field_errors')) return 'Invalid credentials';
    if (msg.contains('phone')) return 'Phone number already registered';
    if (msg.contains('network') || msg.contains('socket')) return 'No internet connection';
    if (msg.contains('timeout')) return 'Connection timed out';

    return 'Something went wrong. Please try again.';
  }
}
