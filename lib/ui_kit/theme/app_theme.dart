// ============================================================
// ConsMas FieldTool Driver — App Theme
// ============================================================
// Wire up in MaterialApp:
//   MaterialApp(theme: AppTheme.light, ...)
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';
import 'app_text_styles.dart';
import 'app_spacing.dart';

abstract class AppTheme {
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.brandAmber,
      primary: AppColors.primaryBlue,
      onPrimary: AppColors.textOnDark,
      primaryContainer: AppColors.brandDarkCard,
      secondary: AppColors.successGreen,
      onSecondary: AppColors.textOnPrimary,
      tertiary: AppColors.brandAmber,
      error: AppColors.errorRed,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: AppColors.background,
    textTheme: AppTypography.textTheme,

    // ── AppBar ──────────────────────────────────────────────
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.primaryBlue,
      foregroundColor: AppColors.textOnDark,
      elevation: 2,
      shadowColor: Colors.black26,
      titleTextStyle: AppTextStyles.appBarTitle,
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.light,
        statusBarColor: Colors.transparent,
      ),
      iconTheme: const IconThemeData(color: AppColors.textOnDark),
    ),

    // ── Cards ───────────────────────────────────────────────
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.lgAll,
        side: const BorderSide(color: AppColors.neutral200),
      ),
      margin: EdgeInsets.zero,
    ),

    // ── Elevated Button (Primary) ────────────────────────────
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primaryBlue,
        foregroundColor: AppColors.textOnDark,
        minimumSize: const Size.fromHeight(AppTouchTargets.btnPrimary),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        textStyle: AppTextStyles.buttonPrimary,
        elevation: 0,
      ),
    ),

    // ── Outlined Button (Secondary) ──────────────────────────
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primaryBlue,
        minimumSize: const Size.fromHeight(AppTouchTargets.btnSecondary),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        side: const BorderSide(color: AppColors.brandAmberDark, width: 1.5),
        textStyle: AppTextStyles.buttonSecondary,
      ),
    ),

    // ── Input Decoration ─────────────────────────────────────
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.neutral50,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      border: OutlineInputBorder(
        borderRadius: AppRadius.smAll,
        borderSide: const BorderSide(color: AppColors.neutral200, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppRadius.smAll,
        borderSide: const BorderSide(color: AppColors.neutral200, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppRadius.smAll,
        borderSide: const BorderSide(color: AppColors.primaryBlue, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: AppRadius.smAll,
        borderSide: const BorderSide(color: AppColors.errorRed, width: 1.5),
      ),
      labelStyle: AppTextStyles.labelSmall,
      hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.textMuted),
      constraints: const BoxConstraints(minHeight: AppTouchTargets.inputField),
    ),

    // ── Divider ──────────────────────────────────────────────
    dividerTheme: const DividerThemeData(
      color: AppColors.neutral200,
      thickness: 1,
      space: 0,
    ),

    // ── Bottom Navigation Bar ────────────────────────────────
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: AppColors.surface,
      selectedItemColor: AppColors.primaryBlue,
      unselectedItemColor: AppColors.neutral400,
      selectedLabelStyle: AppTextStyles.caption.copyWith(
        fontWeight: FontWeight.w700,
        color: AppColors.brandAmberDark,
      ),
      unselectedLabelStyle: AppTextStyles.caption.copyWith(
        fontWeight: FontWeight.w600,
      ),
      showSelectedLabels: true,
      showUnselectedLabels: true,
      elevation: 8,
      type: BottomNavigationBarType.fixed,
    ),

    // ── Tab Bar ──────────────────────────────────────────────
    tabBarTheme: TabBarThemeData(
      labelColor: AppColors.primaryBlue,
      unselectedLabelColor: AppColors.neutral400,
      labelStyle: AppTextStyles.labelSmall.copyWith(
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelStyle: AppTextStyles.labelSmall,
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: AppColors.neutral200,
      indicator: const UnderlineTabIndicator(
        borderSide: BorderSide(color: AppColors.brandAmberDark, width: 2),
      ),
    ),

    // ── Checkbox ─────────────────────────────────────────────
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.successGreen;
        }
        return Colors.transparent;
      }),
      checkColor: WidgetStateProperty.all(AppColors.textOnPrimary),
      side: const BorderSide(color: AppColors.neutral300, width: 2),
      shape: RoundedRectangleBorder(borderRadius: AppRadius.xsAll),
    ),

    // ── Switch (Toggle) ──────────────────────────────────────
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.successGreen;
        }
        return AppColors.neutral300;
      }),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),

    // ── SnackBar ─────────────────────────────────────────────
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.neutral800,
      contentTextStyle: AppTextStyles.bodySmall.copyWith(color: Colors.white),
      actionTextColor: AppColors.accentOrange,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.smAll),
      behavior: SnackBarBehavior.floating,
    ),

    // ── Progress Indicator ───────────────────────────────────
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.primaryBlue,
      linearTrackColor: AppColors.neutral200,
      linearMinHeight: 6,
    ),
  );
}
