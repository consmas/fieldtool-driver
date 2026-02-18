// ============================================================
// ConsMas FieldTool Driver — Spacing, Radius & Shadow Tokens
// ============================================================

import 'package:flutter/material.dart';

abstract class AppSpacing {
  // ── 8px base scale ───────────────────────────────────────
  static const double xs  = 4;
  static const double sm  = 8;
  static const double md  = 12;
  static const double lg  = 16;
  static const double xl  = 24;
  static const double xl2 = 32;
  static const double xl3 = 48;
  static const double xl4 = 64;

  // ── Semantic aliases ─────────────────────────────────────
  static const double screenPadding    = lg;
  static const double cardPadding      = lg;
  static const double cardGap          = md;
  static const double sectionGap       = lg;
  static const double fieldGap         = md;
  static const double inlineGap        = sm;
  static const double iconLabelGap     = xs;
  static const double bottomBarPadding = lg;
  static const double bottomBarHeight  = 64;
  static const double appBarHeight     = 56;
  static const double summaryStripHeight = 130;

  // ── Edge Insets helpers ──────────────────────────────────
  static const EdgeInsets screenPaddingAll =
      EdgeInsets.symmetric(horizontal: lg, vertical: md);
  static const EdgeInsets cardPaddingAll =
      EdgeInsets.all(lg);
  static const EdgeInsets bottomBarPaddingAll =
      EdgeInsets.fromLTRB(lg, md, lg, xl);
}

abstract class AppRadius {
  static const double xs  = 6;
  static const double sm  = 8;
  static const double md  = 12;
  static const double lg  = 16;
  static const double xl  = 24;
  static const double pill = 999;

  static BorderRadius get xsAll  => BorderRadius.circular(xs);
  static BorderRadius get smAll  => BorderRadius.circular(sm);
  static BorderRadius get mdAll  => BorderRadius.circular(md);
  static BorderRadius get lgAll  => BorderRadius.circular(lg);
  static BorderRadius get xlAll  => BorderRadius.circular(xl);
  static BorderRadius get pillAll => BorderRadius.circular(pill);
}

abstract class AppShadows {
  static const List<BoxShadow> sm = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 3, offset: Offset(0, 1),
    ),
    BoxShadow(
      color: Color(0x0F000000),
      blurRadius: 2, offset: Offset(0, 1),
    ),
  ];

  static const List<BoxShadow> md = [
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 12, offset: Offset(0, 4),
    ),
    BoxShadow(
      color: Color(0x0F000000),
      blurRadius: 4, offset: Offset(0, 2),
    ),
  ];

  static const List<BoxShadow> lg = [
    BoxShadow(
      color: Color(0x1F000000),
      blurRadius: 30, offset: Offset(0, 10),
    ),
    BoxShadow(
      color: Color(0x0F000000),
      blurRadius: 8, offset: Offset(0, 4),
    ),
  ];

  static List<BoxShadow> bluePrimary = [
    BoxShadow(
      color: const Color(0xFF4D7AB4).withValues(alpha: 0.35),
      blurRadius: 12, offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> greenSuccess = [
    BoxShadow(
      color: const Color(0xFF208B29).withValues(alpha: 0.35),
      blurRadius: 12, offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> orangeAccent = [
    BoxShadow(
      color: const Color(0xFFFCA002).withValues(alpha: 0.35),
      blurRadius: 12, offset: const Offset(0, 4),
    ),
  ];
}

// ── Touch Target Sizes ────────────────────────────────────────
abstract class AppTouchTargets {
  /// Minimum touch target (WCAG 2.5.5)
  static const double min      = 44;
  static const double iconBtn  = 44;
  static const double listItem = 56;
  static const double btnPrimary    = 52;
  static const double btnSecondary  = 48;
  static const double inputField    = 48;
  static const double checkbox      = 44; // visual 24, touch 44
  static const double toggleRow     = 52; // full row tappable
}
