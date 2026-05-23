import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTypography {
  AppTypography._();
  static const String cairo = 'Cairo';
  static const String inter = 'Inter';

  static const TextStyle appBarTitle = TextStyle(
    fontFamily: cairo, fontSize: 18, fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );

  static const TextStyle sectionHeader = TextStyle(
    fontFamily: cairo, fontSize: 16, fontWeight: FontWeight.bold,
    color: AppColors.accentGold,
  );

  static const TextStyle body = TextStyle(
    fontFamily: cairo, fontSize: 14, fontWeight: FontWeight.normal,
    color: AppColors.textPrimary,
  );

  static const TextStyle smallLabel = TextStyle(
    fontFamily: cairo, fontSize: 12, fontWeight: FontWeight.normal,
    color: AppColors.textSecondary,
  );

  static const TextStyle badge = TextStyle(
    fontFamily: cairo, fontSize: 11, fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
    letterSpacing: 0.4,
  );

  // Monetary — always Inter regardless of locale.
  static const TextStyle money = TextStyle(
    fontFamily: inter, fontSize: 14, fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );

  static const TextStyle moneyLarge = TextStyle(
    fontFamily: inter, fontSize: 20, fontWeight: FontWeight.bold,
    color: AppColors.accentGold,
  );
}
