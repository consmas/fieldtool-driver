// ============================================================
// ConsMas FieldTool Driver — Typography System
// ============================================================
// Uses IBM Plex Sans (body/UI) + IBM Plex Mono (odometer/IDs).
// Add to pubspec.yaml:
//   google_fonts: ^6.1.0
// ============================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

abstract class AppTextStyles {
  // ── Font Families ─────────────────────────────────────────
  static TextStyle get _base => GoogleFonts.ibmPlexSans();
  static TextStyle get _mono => GoogleFonts.ibmPlexMono();

  // ── Display / Headings ────────────────────────────────────
  static TextStyle get displayLarge => _base.copyWith(
    fontSize: 28, fontWeight: FontWeight.w700,
    color: AppColors.textPrimary, letterSpacing: -0.5, height: 1.2,
  );

  static TextStyle get displayMedium => _base.copyWith(
    fontSize: 24, fontWeight: FontWeight.w700,
    color: AppColors.textPrimary, letterSpacing: -0.3, height: 1.25,
  );

  static TextStyle get displaySmall => _base.copyWith(
    fontSize: 20, fontWeight: FontWeight.w700,
    color: AppColors.textPrimary, letterSpacing: -0.2, height: 1.3,
  );

  // ── App Bar / Titles ─────────────────────────────────────
  static TextStyle get appBarTitle => _base.copyWith(
    fontSize: 17, fontWeight: FontWeight.w700,
    color: AppColors.textOnPrimary, letterSpacing: 0,
  );

  static TextStyle get appBarSubtitle => _base.copyWith(
    fontSize: 12, fontWeight: FontWeight.w400,
    color: AppColors.textOnPrimary.withValues(alpha: 0.75),
  );

  // ── Body ─────────────────────────────────────────────────
  static TextStyle get bodyLarge => _base.copyWith(
    fontSize: 16, fontWeight: FontWeight.w500,
    color: AppColors.textPrimary, height: 1.5,
  );

  static TextStyle get bodyMedium => _base.copyWith(
    fontSize: 15, fontWeight: FontWeight.w400,
    color: AppColors.textPrimary, height: 1.5,
  );

  static TextStyle get bodySmall => _base.copyWith(
    fontSize: 14, fontWeight: FontWeight.w400,
    color: AppColors.textSecondary, height: 1.5,
  );

  // ── Labels ────────────────────────────────────────────────
  static TextStyle get labelLarge => _base.copyWith(
    fontSize: 16, fontWeight: FontWeight.w700,
    color: AppColors.textOnPrimary, letterSpacing: 0.2,
  );

  static TextStyle get labelMedium => _base.copyWith(
    fontSize: 14, fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static TextStyle get labelSmall => _base.copyWith(
    fontSize: 12, fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
  );

  // ── Caption / Overline ────────────────────────────────────
  static TextStyle get caption => _base.copyWith(
    fontSize: 12, fontWeight: FontWeight.w400,
    color: AppColors.textMuted, height: 1.4,
  );

  static TextStyle get overline => _base.copyWith(
    fontSize: 11, fontWeight: FontWeight.w700,
    color: AppColors.textMuted,
    letterSpacing: 0.8,
    textBaseline: TextBaseline.alphabetic,
  );

  // ── Mono (Odometer, IDs, Codes) ──────────────────────────
  static TextStyle get monoLarge => _mono.copyWith(
    fontSize: 36, fontWeight: FontWeight.w500,
    color: AppColors.accentOrange, letterSpacing: 4,
  );

  static TextStyle get monoMedium => _mono.copyWith(
    fontSize: 18, fontWeight: FontWeight.w500,
    color: AppColors.primaryBlue, letterSpacing: 2,
  );

  static TextStyle get monoSmall => _mono.copyWith(
    fontSize: 13, fontWeight: FontWeight.w400,
    color: AppColors.textSecondary, letterSpacing: 0.5,
  );

  // ── Status Bar ────────────────────────────────────────────
  static TextStyle get statusBar => _base.copyWith(
    fontSize: 12, fontWeight: FontWeight.w600,
    color: AppColors.textOnPrimary,
  );

  // ── Badge ─────────────────────────────────────────────────
  static TextStyle get badge => _base.copyWith(
    fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.3,
  );

  // ── Button ────────────────────────────────────────────────
  static TextStyle get buttonPrimary => _base.copyWith(
    fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textOnPrimary,
  );

  static TextStyle get buttonSecondary => _base.copyWith(
    fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.primaryBlue,
  );

  // ── Card Section Header ───────────────────────────────────
  static TextStyle get cardTitle => overline.copyWith(
    color: AppColors.textMuted,
  );

  static TextStyle get sectionHeader => _base.copyWith(
    fontSize: 13, fontWeight: FontWeight.w700,
    color: AppColors.textMuted, letterSpacing: 0.6,
  );
}

// ── Theme Extension ───────────────────────────────────────────
// Use this to apply the full typography config to MaterialApp:
//   theme: ThemeData(textTheme: AppTypography.textTheme)
abstract class AppTypography {
  static TextTheme get textTheme => GoogleFonts.ibmPlexSansTextTheme().copyWith(
    displayLarge:  AppTextStyles.displayLarge,
    displayMedium: AppTextStyles.displayMedium,
    displaySmall:  AppTextStyles.displaySmall,
    bodyLarge:     AppTextStyles.bodyLarge,
    bodyMedium:    AppTextStyles.bodyMedium,
    bodySmall:     AppTextStyles.bodySmall,
    labelLarge:    AppTextStyles.labelLarge,
    labelMedium:   AppTextStyles.labelMedium,
    labelSmall:    AppTextStyles.labelSmall,
  );
}
