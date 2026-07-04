import 'package:flutter/material.dart';

/// Spec-exact colors for the agent app. Every screen reads from here.
class AppColors {
  AppColors._();

  static const Color backgroundPrimary   = Color(0xFF1A1A2E);  // logo dark
  static const Color backgroundSecondary = Color(0xFF2D2D44);

  static const Color textPrimary   = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF6B7280);

  static const Color accentOrange  = Color(0xFFFF8C00);  // logo golden-orange
  static const Color accentGold    = Color(0xFFFFB800);  // logo amber gold
  static const Color successGreen  = Color(0xFF22C55E);
  static const Color errorRed      = Color(0xFFEF4444);
  static const Color infoBlue      = Color(0xFF3B82F6);
  static const Color purple        = Color(0xFF8B5CF6);
  static const Color warning       = Color(0xFFF59E0B);

  static const Color inputBg   = Color(0xFF2D2D3A);
  static const Color divider   = Color(0xFF3A3A4A);

  /// rgba(255, 140, 0, 0.08) — card glow.
  static const Color cardShadow = Color(0x14FF8C00);

  /// Returns the spec lifecycle color for a given order status.
  static Color forStatus(String status) {
    switch (status) {
      case 'new':              return accentGold;
      case 'accepted':         return infoBlue;
      case 'preparing':        return accentOrange;
      case 'ready':            return purple;
      case 'out_for_delivery': return purple;
      case 'delivered':        return successGreen;
      case 'cancelled':        return errorRed;
      default:                 return textSecondary;
    }
  }
}
