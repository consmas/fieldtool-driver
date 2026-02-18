// ============================================================
// ConsMas FieldTool Driver — Color Design Tokens
// ============================================================
// Brand palette + semantic aliases for consistent theming.
// All colors pass WCAG AA contrast on their designated surfaces.
// ============================================================

import 'package:flutter/material.dart';

abstract class AppColors {
  // ── Brand Primaries ──────────────────────────────────────
  static const Color primaryBlue     = Color(0xFF4D7AB4);
  static const Color primaryBlueDark = Color(0xFF3A5F8E);
  static const Color primaryBlueMid  = Color(0xFF6A93C7);
  static const Color primaryBlueLight= Color(0xFFEBF1FA);

  static const Color successGreen    = Color(0xFF208B29);
  static const Color successGreenDark= Color(0xFF166A1E);
  static const Color successGreenLight= Color(0xFFE6F4E7);

  static const Color accentOrange    = Color(0xFFFCA002);
  static const Color accentOrangeDark= Color(0xFFC97E00);
  static const Color accentOrangeLight= Color(0xFFFFF3E0);

  // ── Semantic ─────────────────────────────────────────────
  static const Color errorRed        = Color(0xFFD32F2F);
  static const Color errorRedLight   = Color(0xFFFDECEA);
  static const Color warningAmber    = Color(0xFFFFC107);
  static const Color infoBlue        = primaryBlue;

  // ── Neutrals ─────────────────────────────────────────────
  static const Color neutral50  = Color(0xFFF8F9FA);
  static const Color neutral100 = Color(0xFFF0F2F5);
  static const Color neutral200 = Color(0xFFE4E8EE);
  static const Color neutral300 = Color(0xFFCBD2DC);
  static const Color neutral400 = Color(0xFF9AA5B5);
  static const Color neutral500 = Color(0xFF6B7A8D);
  static const Color neutral600 = Color(0xFF4A5568);
  static const Color neutral700 = Color(0xFF2D3748);
  static const Color neutral800 = Color(0xFF1A202C);
  static const Color neutral900 = Color(0xFF0F1420);

  // ── Surface / Background ─────────────────────────────────
  static const Color surface    = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFF0F2F5);
  static const Color surfaceCard = Color(0xFFFFFFFF);

  // ── Text ─────────────────────────────────────────────────
  static const Color textPrimary   = neutral800;
  static const Color textSecondary = neutral600;
  static const Color textMuted     = neutral500;
  static const Color textOnPrimary = Color(0xFFFFFFFF);
  static const Color textOnDark    = Color(0xFFFFFFFF);

  // ── Status Badge Colors ───────────────────────────────────
  static const Color statusAssignedBg   = neutral100;
  static const Color statusAssignedFg   = neutral600;
  static const Color statusEnRouteBg    = primaryBlueLight;
  static const Color statusEnRouteFg    = primaryBlueDark;
  static const Color statusArrivedBg    = accentOrangeLight;
  static const Color statusArrivedFg    = accentOrangeDark;
  static const Color statusOffloadedBg  = Color(0xFFEDE7F6);
  static const Color statusOffloadedFg  = Color(0xFF512DA8);
  static const Color statusCompletedBg  = successGreenLight;
  static const Color statusCompletedFg  = successGreenDark;
  static const Color statusOfflineBg    = errorRedLight;
  static const Color statusOfflineFg    = errorRed;

  // ── Sync Status Colors ────────────────────────────────────
  static const Color syncQueued   = neutral500;
  static const Color syncSyncing  = primaryBlue;
  static const Color syncSynced   = successGreen;
  static const Color syncFailed   = errorRed;
  static const Color syncPending  = accentOrangeDark;
}
