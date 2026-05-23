import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../utils/constants.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  final _api = ApiService();
  final _storage = const FlutterSecureStorage();
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
  bool get isCustomer => _user?.isCustomer ?? false;
  bool get isDriver => _user?.isDriver ?? false;

  Future<void> init() async {
    final token = await _storage.read(key: StorageKeys.accessToken);
    if (token != null) {
      try {
        _user = await _api.getProfile();
        _status = AuthStatus.authenticated;
      } catch (_) {
        _status = AuthStatus.unauthenticated;
      }
    } else {
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
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

  Future<bool> handleSocialLogin({
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

  Future<void> updateFcmToken(String token) async {
    try {
      await _api.updateFcmToken(token);
    } catch (_) {}
  }

  Future<void> logout() async {
    await _api.logout();
    _user = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }

  String _parseError(dynamic e) {
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
