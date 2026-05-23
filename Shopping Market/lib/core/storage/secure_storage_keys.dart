/// Single source of truth for all secure-storage keys. Aliased from the legacy
/// StorageKeys class in utils/constants.dart for back-compat.
class SecureStorageKeys {
  SecureStorageKeys._();

  static const String accessToken      = 'access_token';
  static const String refreshToken     = 'refresh_token';
  static const String userData         = 'user_data';
  static const String biometricToken   = 'biometric_token';
  static const String fcmToken         = 'fcm_token';
  static const String onboardingSeen   = 'onboarding_seen';
  static const String storeId          = 'selected_store_id';
  static const String language         = 'language';
  static const String cartItems        = 'cart_items';
  static const String savedAddresses   = 'saved_addresses';
}
