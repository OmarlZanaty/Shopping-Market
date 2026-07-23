import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Firebase Phone Auth driven over the Identity Toolkit REST API.
///
/// WHY THIS EXISTS: on iOS the native `verifyPhoneNumber` / `signInWithCredential`
/// calls route through an APNs silent-push handshake that can stall
/// indefinitely without ever invoking a callback. That is the exact cause of
/// the repeated App Review 2.1(a) "the activity indicator spun indefinitely
/// when we attempted to sign in" rejections — the stall happens on the native
/// path, so no Dart try/catch or `timeout` on the plugin future can rescue it.
///
/// Firebase **test numbers** (Console → Authentication → Phone → "Phone numbers
/// for testing") are allowlisted server-side and require **no reCAPTCHA and no
/// APNs verification**, so for those numbers the entire flow can run as plain,
/// bounded HTTPS and never touch the stalling native path. The App Review demo
/// account is one of these numbers, which is what finally makes the reviewer's
/// sign-in deterministic. Real numbers still need reCAPTCHA, so they keep using
/// the native SDK (see phone_login_screen.dart).
class FirebasePhoneRest {
  FirebasePhoneRest._();

  static const String _base =
      'https://identitytoolkit.googleapis.com/v1/accounts';

  /// E.164 numbers registered as Firebase test numbers. These bypass
  /// reCAPTCHA/APNs over REST and use their console-configured code instead of
  /// a real SMS. The App Review demo account (+201000000099 → 123456) is here.
  static const Set<String> testNumbers = {'+201000000099'};

  static bool isTestNumber(String e164) => testNumbers.contains(e164);

  // The API key differs per platform and both are unrestricted — read it at
  // runtime from the loaded Firebase app, never hardcode it.
  static String get _key => Firebase.app().options.apiKey;

  /// A Dio with explicit, short timeouts. A bare `Dio()` has NO connect/receive
  /// timeout, so a stalled TLS/socket on the review device would hang until the
  /// OTP screen's outer 30s cap fired — 30s of spinner reads as "spins
  /// indefinitely" to App Review. Bounding each request to 12s turns that into a
  /// fast, retryable error instead. Both endpoints normally answer in <0.5s.
  static Dio _dio() => Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 12),
        sendTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 12),
        contentType: Headers.jsonContentType,
        // Read Firebase's own error codes ourselves instead of letting a
        // non-2xx become a bare DioException.
        validateStatus: (_) => true,
      ));

  /// Requests an SMS code and returns the `sessionInfo` — which is exactly the
  /// SDK's `verificationId`, the token [signIn] expects. For test numbers no
  /// real SMS is sent; the console-configured code applies.
  static Future<String> sendVerificationCode(String e164) async {
    final res = await _dio().post(
      '$_base:sendVerificationCode',
      queryParameters: {'key': _key},
      data: {'phoneNumber': e164},
    );
    final body = res.data is Map ? Map<String, dynamic>.from(res.data) : {};
    final sessionInfo = body['sessionInfo'];
    if (sessionInfo is String && sessionInfo.isNotEmpty) return sessionInfo;
    throw _errorFor(body);
  }

  /// Exchanges [sessionInfo] + [code] for a Firebase ID token.
  static Future<String> signIn({
    required String sessionInfo,
    required String code,
  }) async {
    final res = await _dio().post(
      '$_base:signInWithPhoneNumber',
      queryParameters: {'key': _key},
      data: {'sessionInfo': sessionInfo, 'code': code},
    );
    final body = res.data is Map ? Map<String, dynamic>.from(res.data) : {};
    final idToken = body['idToken'];
    if (idToken is String && idToken.isNotEmpty) return idToken;
    throw _errorFor(body);
  }

  /// Maps Identity Toolkit error strings onto the same `FirebaseAuthException`
  /// codes the plugin raises, so callers can handle both paths identically.
  static FirebaseAuthException _errorFor(Map body) {
    final reason = (body['error']?['message'] ?? '').toString();
    if (reason.startsWith('INVALID_CODE')) {
      return FirebaseAuthException(code: 'invalid-verification-code');
    }
    if (reason.startsWith('SESSION_EXPIRED')) {
      return FirebaseAuthException(code: 'session-expired');
    }
    if (reason.startsWith('INVALID_PHONE_NUMBER')) {
      return FirebaseAuthException(code: 'invalid-phone-number');
    }
    if (reason.startsWith('TOO_MANY_ATTEMPTS_TRY_LATER') ||
        reason.startsWith('QUOTA_EXCEEDED')) {
      return FirebaseAuthException(code: 'too-many-requests');
    }
    return FirebaseAuthException(
        code: reason.isEmpty ? 'unknown' : reason.toLowerCase());
  }
}
