import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppDimensions {
  AppDimensions._();
  static const double cardRadius   = 12.0;
  static const double buttonRadius = 8.0;
  static const double paddingH     = 16.0;
  static const double paddingV     = 12.0;
  static const double cardInner    = 16.0;

  static const BoxShadow cardGlow = BoxShadow(
    color: AppColors.cardShadow,
    blurRadius: 12,
    offset: Offset(0, 4),
  );

  static const Border appBarBottomBorder = Border(
    bottom: BorderSide(color: AppColors.divider, width: 1),
  );
}
