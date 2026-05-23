import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.backgroundPrimary,
        fontFamily: 'Cairo',
        colorScheme: const ColorScheme.dark(
          primary: AppColors.accentOrange,
          onPrimary: AppColors.textPrimary,
          secondary: AppColors.accentGold,
          onSecondary: AppColors.backgroundPrimary,
          surface: AppColors.backgroundSecondary,
          onSurface: AppColors.textPrimary,
          error: AppColors.errorRed,
          onError: AppColors.textPrimary,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.backgroundPrimary,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          centerTitle: false,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            fontFamily: 'Cairo', fontSize: 18,
            fontWeight: FontWeight.bold, color: AppColors.textPrimary,
          ),
          shape: Border(bottom: BorderSide(color: AppColors.divider, width: 1)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accentOrange,
            foregroundColor: AppColors.textPrimary,
            disabledBackgroundColor: AppColors.textSecondary,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
            ),
            textStyle: const TextStyle(
              fontFamily: 'Cairo', fontSize: 15, fontWeight: FontWeight.bold,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.inputBg,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
            borderSide: const BorderSide(color: AppColors.divider, width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
            borderSide: const BorderSide(color: AppColors.divider, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
            borderSide: const BorderSide(color: AppColors.accentOrange, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
            borderSide: const BorderSide(color: AppColors.errorRed, width: 2),
          ),
          hintStyle: const TextStyle(color: AppColors.textSecondary),
        ),
        cardTheme: CardThemeData(
          color: AppColors.backgroundSecondary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppColors.backgroundPrimary,
          selectedItemColor: AppColors.accentOrange,
          unselectedItemColor: AppColors.textSecondary,
          type: BottomNavigationBarType.fixed,
          showSelectedLabels: true,
          showUnselectedLabels: true,
          elevation: 0,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors.accentOrange,
          foregroundColor: AppColors.textPrimary,
        ),
        dividerTheme: const DividerThemeData(
          color: AppColors.divider, thickness: 1, space: 1,
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: AppColors.backgroundSecondary,
          contentTextStyle: TextStyle(color: AppColors.textPrimary),
          behavior: SnackBarBehavior.floating,
        ),
      );
}
