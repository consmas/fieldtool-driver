// ============================================================
// ConsMas FieldTool Driver — Navigation & App Bar Widgets
// ============================================================
// Widgets:
//   • ConsMasAppBar         — primary branded app bar
//   • SurfaceAppBar         — white surface variant for detail screens
//   • TripSummaryStrip      — persistent summary header for Trip Detail
//   • ConsMasBottomNavBar   — branded bottom navigation
//   • StickyBottomBar       — sticky action bar wrapper for long forms
//   • BottomActionBar       — pre-styled 1–2 button bottom bar
// ============================================================

import 'package:flutter/material.dart';
import '../models/enums.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_spacing.dart';
import 'badges.dart';
import 'buttons.dart';

// ─────────────────────────────────────────────────────────────
// CONSMAS APP BAR (primary branded — blue background)
// ─────────────────────────────────────────────────────────────
class ConsMasAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ConsMasAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.onBack,
    this.showBackButton = true,
    this.centerTitle = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final VoidCallback? onBack;
  final bool showBackButton;
  final bool centerTitle;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.primaryBlue,
      elevation: 2,
      shadowColor: Colors.black26,
      centerTitle: centerTitle,
      leading: showBackButton
          ? (leading ?? IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: onBack ?? () => Navigator.of(context).maybePop(),
              tooltip: 'Back',
            ))
          : leading,
      title: Column(
        crossAxisAlignment: centerTitle
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.appBarTitle),
          if (subtitle != null)
            Text(subtitle!, style: AppTextStyles.appBarSubtitle),
        ],
      ),
      actions: [
        ...actions,
        const SizedBox(width: 4),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SURFACE APP BAR (white — used inside modal/sub-screen flows)
// ─────────────────────────────────────────────────────────────
class SurfaceAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SurfaceAppBar({
    super.key,
    required this.title,
    this.trailing,
    this.onBack,
  });

  final String title;
  final Widget? trailing;
  final VoidCallback? onBack;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 1,
      shadowColor: AppColors.neutral200,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
        onPressed: onBack ?? () => Navigator.of(context).maybePop(),
      ),
      title: Text(title,
          style: AppTextStyles.appBarTitle.copyWith(color: AppColors.textPrimary)),
      actions: [
        if (trailing != null) trailing!,
        const SizedBox(width: 4),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Divider(height: 1, color: AppColors.neutral200),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// TRIP SUMMARY STRIP
// Persistent header on Trip Detail Dashboard.
// Typically placed as a SliverPersistentHeader or inside a
// Column above a scrollable body.
// Usage:
//   TripSummaryStrip(
//     tripId: 'TRP-20251104-009',
//     destination: 'Cape Town CBD',
//     waybill: 'WB-44821',
//     eta: '14:30 (2h 18m)',
//     distanceRemaining: '124 km left',
//     status: TripStatus.enRoute,
//     lastUpdated: '2m ago',
//     quickActions: [...],
//   )
// ─────────────────────────────────────────────────────────────
class TripSummaryStrip extends StatelessWidget {
  const TripSummaryStrip({
    super.key,
    required this.destination,
    required this.waybill,
    required this.eta,
    required this.distanceRemaining,
    required this.status,
    required this.quickActions,
    this.lastUpdated,
    this.speed,
  });

  final String destination;
  final String waybill;
  final String eta;
  final String distanceRemaining;
  final TripStatus status;
  final List<({IconData icon, String label, VoidCallback onTap})> quickActions;
  final String? lastUpdated;
  final String? speed;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primaryBlueDark,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status + last updated
          Row(children: [
            _StatusPill(status: status),
            const Spacer(),
            if (lastUpdated != null)
              Text(
                'Updated $lastUpdated',
                style: AppTextStyles.caption.copyWith(
                  color: Colors.white54, fontSize: 10,
                ),
              ),
          ]),
          const SizedBox(height: AppSpacing.sm),
          // Destination
          Row(children: [
            const Icon(Icons.place, color: Colors.white70, size: 14),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                destination,
                style: AppTextStyles.displaySmall.copyWith(color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
          const SizedBox(height: AppSpacing.sm),
          // Waybill / ETA / Distance
          Row(children: [
            _SummaryChip(label: 'Waybill', value: waybill),
            const SizedBox(width: AppSpacing.lg),
            _SummaryChip(label: 'ETA', value: eta),
            const SizedBox(width: AppSpacing.lg),
            _SummaryChip(label: 'Distance', value: distanceRemaining),
            if (speed != null) ...[
              const SizedBox(width: AppSpacing.lg),
              _SummaryChip(label: 'Speed', value: speed!),
            ],
          ]),
          const SizedBox(height: AppSpacing.md),
          // Quick actions row
          Row(
            children: quickActions.map((qa) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: QuickActionButton(
                  icon: qa.icon,
                  label: qa.label,
                  onPressed: qa.onTap,
                  onDark: true,
                ),
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final TripStatus status;

  Color get _bg => switch (status) {
    TripStatus.enRoute   => Colors.white.withValues(alpha: 0.15),
    TripStatus.arrived   => AppColors.accentOrange.withValues(alpha: 0.25),
    TripStatus.offloaded => AppColors.successGreen.withValues(alpha: 0.25),
    TripStatus.completed => AppColors.successGreen.withValues(alpha: 0.25),
    _                    => Colors.white.withValues(alpha: 0.10),
  };

  Color get _fg => switch (status) {
    TripStatus.enRoute   => const Color(0xFF90C4FF),
    TripStatus.arrived   => const Color(0xFFFFC947),
    TripStatus.offloaded => const Color(0xFF69E876),
    TripStatus.completed => const Color(0xFF69E876),
    _                    => Colors.white70,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: AppRadius.pillAll,
        border: Border.all(color: _fg.withValues(alpha: 0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (status.isLive)
          Padding(
            padding: const EdgeInsets.only(right: 5),
            child: PulseDot(color: _fg, size: 5),
          ),
        Text(
          status.label.toUpperCase(),
          style: AppTextStyles.badge.copyWith(color: _fg, fontSize: 10, letterSpacing: 0.5),
        ),
      ]),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: AppTextStyles.caption.copyWith(color: Colors.white54, fontSize: 10)),
      const SizedBox(height: 2),
      Text(value, style: AppTextStyles.labelSmall.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
    ],
  );
}

// ─────────────────────────────────────────────────────────────
// CONSMAS BOTTOM NAV BAR
// Branded 4-tab bottom navigation.
// Usage (in Scaffold):
//   bottomNavigationBar: ConsMasBottomNavBar(
//     currentIndex: _tab,
//     onTap: (i) => setState(() => _tab = i),
//     pendingSyncCount: 3,
//   )
// ─────────────────────────────────────────────────────────────
class ConsMasBottomNavBar extends StatelessWidget {
  const ConsMasBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.pendingSyncCount = 0,
  });

  final int currentIndex;
  final void Function(int) onTap;
  final int pendingSyncCount;

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: onTap,
      items: [
        const BottomNavigationBarItem(
          icon: Icon(Icons.folder_outlined),
          activeIcon: Icon(Icons.folder),
          label: 'Trips',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.location_on_outlined),
          activeIcon: Icon(Icons.location_on),
          label: 'Track',
        ),
        BottomNavigationBarItem(
          icon: Badge(
            isLabelVisible: pendingSyncCount > 0,
            label: Text('$pendingSyncCount'),
            child: const Icon(Icons.upload_outlined),
          ),
          activeIcon: Badge(
            isLabelVisible: pendingSyncCount > 0,
            label: Text('$pendingSyncCount'),
            child: const Icon(Icons.upload),
          ),
          label: 'Sync',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.person_outline),
          activeIcon: Icon(Icons.person),
          label: 'Profile',
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// STICKY BOTTOM BAR
// Wraps Scaffold body to add a sticky bottom action area.
// Prevents content from being obscured behind the bar.
// Usage:
//   StickyBottomBar(
//     bottomBar: BottomActionBar(
//       primary: AppPrimaryButton(label: 'Save', onPressed: _save),
//     ),
//     child: ListView(...),
//   )
// ─────────────────────────────────────────────────────────────
class StickyBottomBar extends StatelessWidget {
  const StickyBottomBar({
    super.key,
    required this.child,
    required this.bottomBar,
  });

  final Widget child;
  final Widget bottomBar;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: child),
        bottomBar,
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// BOTTOM ACTION BAR
// 1–2 action buttons anchored at the bottom of a screen.
// ─────────────────────────────────────────────────────────────
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({
    super.key,
    required this.primary,
    this.secondary,
    this.saveState,
  });

  final Widget primary;
  final Widget? secondary;

  /// Optional sync state shown above the buttons
  final SyncStatus? saveState;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg, AppSpacing.md, AppSpacing.lg,
        AppSpacing.md + (bottomInset > 0 ? bottomInset : AppSpacing.sm),
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.neutral200)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (saveState != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: SaveStateIndicator(state: saveState!),
            ),
          Row(children: [
            if (secondary != null) ...[
              Expanded(flex: 4, child: secondary!),
              const SizedBox(width: AppSpacing.sm),
            ],
            Expanded(flex: secondary != null ? 6 : 10, child: primary),
          ]),
        ],
      ),
    );
  }
}
