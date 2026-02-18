import 'package:flutter/material.dart';

import '../../ui_kit/theme/app_colors.dart';
import '../../ui_kit/theme/app_theme.dart' as kit;

class AppTheme {
  // Compatibility aliases used by existing screens.
  static const Color primary = AppColors.primaryBlue;
  static const Color secondary = AppColors.successGreen;
  static const Color accent = AppColors.accentOrange;
  static const Color primaryDark = AppColors.primaryBlueDark;
  static const Color primaryLight = AppColors.primaryBlueLight;
  static const Color successLight = AppColors.successGreenLight;
  static const Color warningLight = AppColors.accentOrangeLight;
  static const Color danger = AppColors.errorRed;
  static const Color dangerLight = AppColors.errorRedLight;
  static const Color background = AppColors.background;
  static const Color surface = AppColors.surface;
  static const Color textPrimary = AppColors.textPrimary;
  static const Color textSecondary = AppColors.textSecondary;
  static const Color textMuted = AppColors.textMuted;
  static const Color border = AppColors.neutral200;

  static ThemeData build() => kit.AppTheme.light;
}
