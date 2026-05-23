import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Spec-exact typography. Locale-aware font picker — Cairo for Arabic, Inter
/// for English. Monetary values always use Inter regardless of locale.
class AppTypography {
  AppTypography._();

  static const String fontFamilyAr   = 'Cairo';
  static const String fontFamilyEn   = 'Inter';
  static const String fontFamilyMoney = 'Inter';  // always Inter for currency

  /// Picks Cairo or Inter based on the current locale's language code.
  static String fontFor(Locale locale) =>
      locale.languageCode == 'ar' ? fontFamilyAr : fontFamilyEn;

  /// AppBar title: 18sp bold.
  static TextStyle appBarTitle(Locale locale) => TextStyle(
        fontFamily: fontFor(locale),
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
      );

  /// Headings: 16sp bold.
  static TextStyle heading(Locale locale) => TextStyle(
        fontFamily: fontFor(locale),
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
      );

  /// Body: 14sp normal.
  static TextStyle body(Locale locale) => TextStyle(
        fontFamily: fontFor(locale),
        fontSize: 14,
        fontWeight: FontWeight.normal,
        color: AppColors.textPrimary,
      );

  /// Captions: 12sp normal, textSecondary.
  static TextStyle caption(Locale locale) => TextStyle(
        fontFamily: fontFor(locale),
        fontSize: 12,
        fontWeight: FontWeight.normal,
        color: AppColors.textSecondary,
      );

  /// Monetary values — Inter, regardless of locale.
  static const TextStyle money = TextStyle(
    fontFamily: fontFamilyMoney,
    fontSize: 14,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );

  /// Discounted (new) price — gold, bold, Inter.
  static const TextStyle moneyDiscount = TextStyle(
    fontFamily: fontFamilyMoney,
    fontSize: 14,
    fontWeight: FontWeight.bold,
    color: AppColors.accentGold,
  );

  /// Original price (struck through).
  static const TextStyle moneyOriginal = TextStyle(
    fontFamily: fontFamilyMoney,
    fontSize: 12,
    color: AppColors.textSecondary,
    decoration: TextDecoration.lineThrough,
  );

  /// Per-unit suffix next to price, e.g. "/ كجم"
  static const TextStyle unitSuffix = TextStyle(
    fontFamily: fontFamilyEn,
    fontSize: 11,
    color: AppColors.textSecondary,
  );
}
