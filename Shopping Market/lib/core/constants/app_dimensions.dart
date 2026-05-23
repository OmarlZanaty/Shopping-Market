import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Spec-exact dimensions, radii, and shadows.
class AppDimensions {
  AppDimensions._();

  static const double cardRadius      = 12.0;
  static const double buttonRadius    = 8.0;
  static const double paddingH        = 16.0;  // horizontal standard padding
  static const double paddingV        = 12.0;
  static const double cardElevation   = 0;     // shadow via BoxShadow only

  static const double iconSm  = 16;
  static const double iconMd  = 20;
  static const double iconLg  = 24;

  static const double avatarSm = 32;
  static const double avatarMd = 48;
  static const double avatarLg = 64;

  /// Card shadow — orange tint per spec.
  static const BoxShadow cardShadow = BoxShadow(
    color: AppColors.cardShadowOrange,
    blurRadius: 12,
    offset: Offset(0, 4),
  );

  static List<BoxShadow> get cardShadows => const [cardShadow];

  /// AppBar bottom 1px border.
  static const Border appBarBottomBorder = Border(
    bottom: BorderSide(color: AppColors.appBarDivider, width: 1),
  );
}
