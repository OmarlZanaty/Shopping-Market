import 'package:flutter/material.dart';

/// Spec-exact color palette. EVERY color used in the customer app comes from
/// here. No inline hex codes anywhere else in the codebase.
class AppColors {
  AppColors._();

  // ── Backgrounds ──────────────────────────────────────────────────────────
  static const Color backgroundPrimary   = Color(0xFF0F0F1A);
  static const Color backgroundSecondary = Color(0xFF2D2D3A);
  static const Color backgroundTertiary  = Color(0xFFF3F4F6);

  // ── Text ─────────────────────────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF6B7280);

  // ── Accents ──────────────────────────────────────────────────────────────
  static const Color accentOrange  = Color(0xFFFF6B35);
  static const Color accentGold    = Color(0xFFFFC107);
  static const Color successGreen  = Color(0xFF22C55E);
  static const Color errorRed      = Color(0xFFEF4444);
  static const Color infoBlue      = Color(0xFF3B82F6);
  static const Color purple        = Color(0xFF8B5CF6);

  // ── Effects ──────────────────────────────────────────────────────────────
  /// rgba(255, 107, 53, 0.08)
  static const Color cardShadowOrange = Color(0x14FF6B35);

  /// AppBar bottom 1px divider.
  static const Color appBarDivider = Color(0xFF3A3A4A);

  // ── Gradients ────────────────────────────────────────────────────────────
  static const LinearGradient chatGradient = LinearGradient(
    colors: [accentOrange, accentGold],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Order lifecycle colors (EXACT per spec) ──────────────────────────────
  /// Returns the colour for a given order status string.
  /// new → gold (#FFC107)
  /// accepted → infoBlue (#3B82F6)
  /// preparing → accentOrange (#FF6B35)
  /// out_for_delivery → purple (#8B5CF6)
  /// delivered → successGreen (#22C55E)
  /// cancelled → errorRed (#EF4444)
  static Color forOrderStatus(String status) {
    switch (status) {
      case 'new':              return accentGold;
      case 'accepted':         return infoBlue;
      case 'preparing':        return accentOrange;
      case 'out_for_delivery': return purple;
      case 'delivered':        return successGreen;
      case 'cancelled':        return errorRed;
      default:                 return textSecondary;
    }
  }
}
