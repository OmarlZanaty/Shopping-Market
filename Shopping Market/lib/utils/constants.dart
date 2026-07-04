import 'package:flutter/material.dart';

class AppConfig {
  static const String baseUrl = 'http://34.124.228.3:8000/api/v1';
  static const String wsBaseUrl = 'ws://34.124.228.3:8000';
  static const String googleMapsApiKey = 'YOUR_GOOGLE_MAPS_API_KEY';
  static const int connectTimeout = 60000;
  static const int receiveTimeout = 60000;
}

/// Delivery-zone limits. Defaults are used offline / before the first fetch,
/// then overwritten from GET /notifications/settings/ (admin-editable keys:
/// delivery_radius_km, store_latitude, store_longitude).
class DeliveryConfig {
  static double radiusKm   = 4.0;
  static double storeLat   = 29.227922;
  static double storeLng   = 32.622006;

  /// Merge a raw {key: value} settings map. Silently ignores bad/absent keys.
  static void applySettings(Map<String, dynamic> s) {
    radiusKm = _toDouble(s['delivery_radius_km'], radiusKm);
    storeLat = _toDouble(s['store_latitude'], storeLat);
    storeLng = _toDouble(s['store_longitude'], storeLng);
  }

  static double _toDouble(dynamic v, double fallback) {
    if (v == null) return fallback;
    return double.tryParse(v.toString()) ?? fallback;
  }
}

/// Loyalty-points economics, admin-controlled via AppSettings and mirrored here
/// from GET /notifications/settings/. Mirrors apps/orders/loyalty.py. Defaults
/// keep the legacy 1pt/EGP earn + 0.05 EGP/pt redeem behaviour.
class LoyaltyConfig {
  static bool   enabled          = true;
  static int    earnPoints       = 1;    // points granted per earn block
  static double earnPerEgp       = 1;    // block size in EGP
  static int    redeemPoints     = 20;   // points per redeem block
  static double redeemEgp        = 1;    // EGP discount per redeem block
  static int    minRedeem        = 0;
  static double maxRedeemPercent = 100;

  /// EGP value of a single point.
  static double get egpPerPoint {
    if (redeemPoints > 0 && redeemEgp > 0) return redeemEgp / redeemPoints;
    return 0.05; // legacy fallback
  }

  /// Points earned for spending [amount] EGP.
  static int pointsForAmount(double amount) {
    if (!enabled || amount <= 0 || earnPerEgp <= 0) return 0;
    return (amount / earnPerEgp).floor() * earnPoints;
  }

  /// EGP discount for redeeming [points].
  static double valueForPoints(int points) =>
      points <= 0 ? 0 : points * egpPerPoint;

  static void applySettings(Map<String, dynamic> s) {
    if (s.containsKey('loyalty_enabled')) {
      enabled = s['loyalty_enabled'].toString().trim() != '0' &&
          s['loyalty_enabled'].toString().toLowerCase() != 'false';
    }
    earnPoints       = _int(s['loyalty_earn_points'], earnPoints);
    earnPerEgp       = _dbl(s['loyalty_earn_per_egp'], earnPerEgp);
    redeemPoints     = _int(s['loyalty_redeem_points'], redeemPoints);
    redeemEgp        = _dbl(s['loyalty_redeem_egp'], redeemEgp);
    minRedeem        = _int(s['loyalty_min_redeem'], minRedeem);
    maxRedeemPercent = _dbl(s['loyalty_max_redeem_percent'], maxRedeemPercent);
  }

  static int _int(dynamic v, int fb) =>
      v == null ? fb : (int.tryParse(v.toString()) ?? double.tryParse(v.toString())?.toInt() ?? fb);
  static double _dbl(dynamic v, double fb) =>
      v == null ? fb : (double.tryParse(v.toString()) ?? fb);
}

// ─── Brand Colors (aligned with Shopping Market logo) ─────────────────────────
class AppColors {
  // Core dark — matches logo background
  static const Color midnight   = Color(0xFF1A1A2E);
  static const Color sapphire   = Color(0xFF2E5E99);
  static const Color sky        = Color(0xFF7BA4D0);
  static const Color ice        = Color(0xFFFFF8F0);   // warm tint

  // Primary accent — golden-orange from logo cart icon
  static const Color coral      = Color(0xFFFF8C00);   // golden orange
  static const Color gold       = Color(0xFFFFB800);   // amber gold
  static const Color mint       = Color(0xFF2FBE8F);
  static const Color watermelon = Color(0xFFFB7185);
  static const Color peach      = Color(0xFFFFF3E0);   // warm peach
  static const Color seafoam    = Color(0xFFECFDF5);
  static const Color lemon      = Color(0xFFFFFBEB);

  // Utility
  static const Color white      = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFF5F5F7);
  static const Color cardBg     = Color(0xFFFFFFFF);
  static const Color border     = Color(0xFFEEEEF2);
  static const Color textMain   = Color(0xFF1A1A2E);
  static const Color textSub    = Color(0xFF7BA4D0);
  static const Color textMuted  = Color(0xFF9CA3AF);
  static const Color success    = Color(0xFF2FBE8F);
  static const Color error      = Color(0xFFEF4444);
  static const Color warning    = Color(0xFFFFB800);

  // Gradients
  static const LinearGradient headerGradient = LinearGradient(
    colors: [midnight, Color(0xFF2D2D4E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient coralGradient = LinearGradient(
    colors: [coral, Color(0xFFFF6B00)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient goldGradient = LinearGradient(
    colors: [gold, Color(0xFFFF8C00)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient mintGradient = LinearGradient(
    colors: [mint, Color(0xFF20a07a)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

// ─── App Theme ────────────────────────────────────────────────────────────────
class AppTheme {
  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.sapphire,
      primary: AppColors.sapphire,
      secondary: AppColors.coral,
      background: AppColors.background,
      surface: AppColors.cardBg,
    ),
    fontFamily: 'Cairo',
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.midnight,
      foregroundColor: AppColors.white,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: 'Cairo',
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.white,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.coral,
        foregroundColor: AppColors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.sapphire, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
    ),
    cardTheme: CardThemeData(
      color: AppColors.cardBg,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.border, width: 1),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.white,
      selectedItemColor: AppColors.coral,
      unselectedItemColor: AppColors.textMuted,
      showSelectedLabels: true,
      showUnselectedLabels: true,
      type: BottomNavigationBarType.fixed,
    ),
  );
}

// ─── Text Styles ──────────────────────────────────────────────────────────────
class AppText {
  static const TextStyle h1 = TextStyle(
    fontSize: 24, fontWeight: FontWeight.w700,
    color: AppColors.textMain, fontFamily: 'Cairo',
  );
  static const TextStyle h2 = TextStyle(
    fontSize: 18, fontWeight: FontWeight.w700,
    color: AppColors.textMain, fontFamily: 'Cairo',
  );
  static const TextStyle h3 = TextStyle(
    fontSize: 15, fontWeight: FontWeight.w600,
    color: AppColors.textMain, fontFamily: 'Cairo',
  );
  static const TextStyle body = TextStyle(
    fontSize: 13, fontWeight: FontWeight.w400,
    color: AppColors.textMain, fontFamily: 'Cairo',
  );
  static const TextStyle caption = TextStyle(
    fontSize: 11, fontWeight: FontWeight.w400,
    color: AppColors.textMuted, fontFamily: 'Cairo',
  );
  static const TextStyle price = TextStyle(
    fontSize: 16, fontWeight: FontWeight.w700,
    color: AppColors.sapphire, fontFamily: 'Cairo',
  );
  static const TextStyle priceLarge = TextStyle(
    fontSize: 22, fontWeight: FontWeight.w700,
    color: AppColors.sapphire, fontFamily: 'Cairo',
  );
}

// ─── Spacing & Radius ─────────────────────────────────────────────────────────
class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
}

class AppRadius {
  static const double sm  = 8;
  static const double md  = 12;
  static const double lg  = 16;
  static const double xl  = 20;
  static const double xxl = 24;
  static const double pill = 100;
}

// ─── Order Status ─────────────────────────────────────────────────────────────
class OrderStatus {
  static const String newOrder      = 'new';
  static const String preparing     = 'preparing';
  static const String outForDelivery= 'out_for_delivery';
  static const String delivered     = 'delivered';
  static const String cancelled     = 'cancelled';

  static Color color(String status) {
    switch (status) {
      case newOrder:       return AppColors.sapphire;
      case preparing:      return AppColors.gold;
      case outForDelivery: return AppColors.coral;
      case delivered:      return AppColors.mint;
      case cancelled:      return AppColors.error;
      default:             return AppColors.textMuted;
    }
  }

  static String labelAr(String status) {
    switch (status) {
      case newOrder:       return 'جديد';
      case preparing:      return 'يتم التحضير';
      case outForDelivery: return 'خرج للتوصيل';
      case delivered:      return 'تم التسليم';
      case cancelled:      return 'ملغي';
      default:             return status;
    }
  }

  static String labelEn(String status) {
    switch (status) {
      case newOrder:       return 'New';
      case preparing:      return 'Preparing';
      case outForDelivery: return 'Out for Delivery';
      case delivered:      return 'Delivered';
      case cancelled:      return 'Cancelled';
      default:             return status;
    }
  }

  static IconData icon(String status) {
    switch (status) {
      case newOrder:       return Icons.fiber_new_rounded;
      case preparing:      return Icons.shopping_basket_rounded;
      case outForDelivery: return Icons.delivery_dining_rounded;
      case delivered:      return Icons.check_circle_rounded;
      case cancelled:      return Icons.cancel_rounded;
      default:             return Icons.help_rounded;
    }
  }
}

// ─── Storage Keys ─────────────────────────────────────────────────────────────
class StorageKeys {
  static const String accessToken  = 'access_token';
  static const String refreshToken = 'refresh_token';
  static const String userData     = 'user_data';
  static const String language     = 'language';
  static const String biometricToken = 'biometric_token';
  static const String cartItems    = 'cart_items';
  static const String savedAddresses = 'saved_addresses';
  static const String fcmToken     = 'fcm_token';
}
