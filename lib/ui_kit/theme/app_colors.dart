// ============================================================
// ConsMas FieldTool Driver — Color Design Tokens
// ============================================================
// Brand palette + semantic aliases for consistent theming.
// All colors pass WCAG AA contrast on their designated surfaces.
// ============================================================

import 'package:flutter/material.dart';

abstract class AppColors {
  // ── Axle Brand Primaries ─────────────────────────────────
  static const Color brandAmber      = Color(0xFFF59E0B);
  static const Color brandAmberLight = Color(0xFFFBBF24);
  static const Color brandAmberDark  = Color(0xFFD97706);
  static const Color brandAmberDeep  = Color(0xFFB45309);

  static const Color brandDark       = Color(0xFF0A0E1A);
  static const Color brandDarkCard   = Color(0xFF111827);
  static const Color brandDarkSurface= Color(0xFF0F172A);
  static const Color brandSlate      = Color(0xFF1E293B);

  // ── Backward-compatible aliases used across app ──────────
  static const Color primaryBlue     = brandDarkSurface;
  static const Color primaryBlueDark = brandDark;
  static const Color primaryBlueMid  = brandSlate;
  static const Color primaryBlueLight= Color(0xFFE2E8F0);

  static const Color successGreen    = Color(0xFF208B29);
  static const Color successGreenDark= Color(0xFF166A1E);
  static const Color successGreenLight= Color(0xFFE6F4E7);

  static const Color accentOrange    = brandAmber;
  static const Color accentOrangeDark= brandAmberDark;
  static const Color accentOrangeLight= Color(0xFFFFF4DE);

  // ── Semantic ─────────────────────────────────────────────
  static const Color errorRed        = Color(0xFFD32F2F);
  static const Color errorRedLight   = Color(0xFFFDECEA);
  static const Color warningAmber    = brandAmberLight;
  static const Color infoBlue        = primaryBlue;

  // ── Neutrals ─────────────────────────────────────────────
  static const Color neutral50  = Color(0xFFF8FAFC);
  static const Color neutral100 = Color(0xFFF1F5F9);
  static const Color neutral200 = Color(0xFFE2E8F0);
  static const Color neutral300 = Color(0xFFCBD5E1);
  static const Color neutral400 = Color(0xFF94A3B8);
  static const Color neutral500 = Color(0xFF64748B);
  static const Color neutral600 = Color(0xFF475569);
  static const Color neutral700 = Color(0xFF334155);
  static const Color neutral800 = Color(0xFF1E293B);
  static const Color neutral900 = Color(0xFF0F172A);

  // ── Surface / Background ─────────────────────────────────
  static const Color surface    = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFF8FAFC);
  static const Color surfaceCard = Color(0xFFFFFFFF);

  // ── Text ─────────────────────────────────────────────────
  static const Color textPrimary   = neutral800;
  static const Color textSecondary = neutral600;
  static const Color textMuted     = neutral500;
  static const Color textOnPrimary = Color(0xFFFFFFFF);
  static const Color textOnDark    = neutral50;

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
