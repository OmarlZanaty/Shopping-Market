import 'package:flutter/foundation.dart';

/// API constants. Pulls from .env at runtime via flutter_dotenv (wired in main).
/// Falls back to safe defaults if .env isn't loaded.
class ApiConstants {
  ApiConstants._();

  /// HTTP base URL for the Django backend. Override via .env API_BASE_URL.
  static String get baseUrl {
    const fromEnv = String.fromEnvironment('API_BASE_URL');
    if (fromEnv.isNotEmpty) return fromEnv;
    return 'https://63-186-157-245.sslip.io/api/v1';
  }

  /// WebSocket base URL.
  static String get wsBaseUrl {
    const fromEnv = String.fromEnvironment('WS_BASE_URL');
    if (fromEnv.isNotEmpty) return fromEnv;
    return 'wss://63-186-157-245.sslip.io';
  }

  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);

  // Endpoint paths — single source of truth.
  static const String authSendOtp     = '/auth/send-otp/';
  static const String authVerifyOtp   = '/auth/verify-otp/';
  static const String authLogin       = '/auth/login/';
  static const String authRefresh     = '/auth/refresh/';
  static const String authLogout      = '/auth/logout/';
  static const String authSocial      = '/auth/social/';
  static const String authMe          = '/auth/me/';
  static const String authFcm         = '/auth/fcm-token/';

  static const String storesConfig    = '/stores/config/';
  static const String storesList      = '/stores/';

  static const String products        = '/products/';
  static const String categories      = '/products/categories/';
  static const String banners         = '/products/banners/';
  static const String waitlist        = '/products/waitlist/';

  static const String orders          = '/orders/';
  static const String ordersCreate    = '/orders/create/';

  static const String walletBalance   = '/wallet/balance/';
  static const String walletTxns      = '/wallet/transactions/';

  static const String notifications   = '/notifications/my/';
  static const String notificationsReadAll = '/notifications/read-all/';

  static const String ratings         = '/ratings/';
  static const String promotionsValidate = '/promotions/promotions/validate/';

  static const String uploadsPresign  = '/uploads/presign/';
}
