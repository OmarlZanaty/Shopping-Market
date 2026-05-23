import 'package:flutter/material.dart';

class AppConfig {
  static const String baseUrl = 'http://34.124.228.3:8000/api/v1';
  static const String wsBaseUrl = 'ws://34.124.228.3:8000';
  static const String googleMapsApiKey = 'YOUR_GOOGLE_MAPS_API_KEY';
  static const int connectTimeout = 60000;
  static const int receiveTimeout = 60000;
}

// ─── Brand Colors ─────────────────────────────────────────────────────────────
class AppColors {
  // Sapphire Veil (base palette)
  static const Color midnight   = Color(0xFF0D2440);
  static const Color sapphire   = Color(0xFF2E5E99);
  static const Color sky        = Color(0xFF7BA4D0);
  static const Color ice        = Color(0xFFE7F0FA);

  // Summer Beach palette (accent)
  static const Color coral      = Color(0xFFF97316);
  static const Color gold       = Color(0xFFFBBF24);
  static const Color mint       = Color(0xFF2FBE8F);
  static const Color watermelon = Color(0xFFFB7185);
  static const Color peach      = Color(0xFFFFF7ED);
  static const Color seafoam    = Color(0xFFECFDF5);
  static const Color lemon      = Color(0xFFFFFBEB);

  // Utility
  static const Color white      = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFF0F5FB);
  static const Color cardBg     = Color(0xFFFFFFFF);
  static const Color border     = Color(0xFFE8F0FA);
  static const Color textMain   = Color(0xFF0D2440);
  static const Color textSub    = Color(0xFF7BA4D0);
  static const Color textMuted  = Color(0xFF9CA3AF);
  static const Color success    = Color(0xFF2FBE8F);
  static const Color error      = Color(0xFFEF4444);
  static const Color warning    = Color(0xFFFBBF24);

  // Gradients
  static const LinearGradient headerGradient = LinearGradient(
    colors: [midnight, Color(0xFF1a3a6e)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient coralGradient = LinearGradient(
    colors: [coral, Color(0xFFea6009)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
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
