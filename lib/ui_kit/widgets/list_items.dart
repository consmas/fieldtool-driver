// ============================================================
// ConsMas FieldTool Driver — List Item Widgets
// ============================================================
// Widgets:
//   • TripCard              — trip list item with status accent
//   • SyncQueueItem         — individual sync queue row
//   • SyncQueueSection      — grouped sync queue list
//   • EmptyState            — friendly empty/error state
//   • ConfirmationHero      — green/blue hero for confirm screens
// ============================================================

import 'package:flutter/material.dart';
import '../models/enums.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_spacing.dart';
import 'badges.dart';
import 'buttons.dart';

// ─────────────────────────────────────────────────────────────
// TRIP CARD
// Tappable card in the trips list with left status accent.
// Usage:
//   TripCard(
//     tripId: 'TRP-20251104-009',
//     destination: 'Cape Town CBD',
//     origin: 'Johannesburg',
//     waybill: 'WB-44821',
//     eta: '14:30',
//     status: TripStatus.enRoute,
//     hasPendingSync: true,
//     onTap: () => navigator.push(...),
//   )
// ─────────────────────────────────────────────────────────────
class TripCard extends StatelessWidget {
  const TripCard({
    super.key,
    required this.tripId,
    required this.destination,
    required this.status,
    this.origin,
    this.waybill,
    this.eta,
    this.departTime,
    this.hasPendingSync = false,
    this.onTap,
  });

  final String tripId;
  final String destination;
  final TripStatus status;
  final String? origin;
  final String? waybill;
  final String? eta;
  final String? departTime;
  final bool hasPendingSync;
  final VoidCallback? onTap;

  Color get _accentColor => switch (status) {
    TripStatus.enRoute   => AppColors.successGreen,
    TripStatus.arrived   => AppColors.accentOrange,
    TripStatus.offloaded => const Color(0xFF7B1FA2),
    TripStatus.completed => AppColors.neutral300,
    TripStatus.assigned  => AppColors.primaryBlue,
  };

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: AppRadius.lgAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.lgAll,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: AppRadius.lgAll,
            border: Border.all(color: AppColors.neutral200),
            boxShadow: AppShadows.sm,
          ),
          child: ClipRRect(
            borderRadius: AppRadius.lgAll,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Accent bar
                  Container(width: 4, color: _accentColor),
                  // Content
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  tripId,
                                  style: AppTextStyles.labelMedium.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              TripStatusBadge(status: status),
                            ],
                          ),
                          const SizedBox(height: 6),
                          // Origin → Destination
                          Row(children: [
                            const Icon(Icons.place_outlined, size: 14, color: AppColors.textMuted),
                            const SizedBox(width: 4),
                            if (origin != null) ...[
                              Text(origin!, style: AppTextStyles.bodySmall),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 4),
                                child: Icon(Icons.arrow_forward, size: 12, color: AppColors.textMuted),
                              ),
                            ],
                            Expanded(
                              child: Text(
                                destination,
                                style: AppTextStyles.bodySmall.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ]),
                          const SizedBox(height: 8),
                          // Footer chips
                          Row(children: [
                            if (waybill != null) _chip(Icons.receipt_outlined, waybill!),
                            if (eta != null) ...[
                              const SizedBox(width: 12),
                              _chip(Icons.schedule, 'ETA $eta'),
                            ],
                            if (departTime != null) ...[
                              const SizedBox(width: 12),
                              _chip(Icons.departure_board, 'Depart $departTime'),
                            ],
                            const Spacer(),
                            if (hasPendingSync)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.accentOrangeLight,
                                  borderRadius: AppRadius.pillAll,
                                ),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  const Icon(Icons.sync, size: 10, color: AppColors.accentOrangeDark),
                                  const SizedBox(width: 3),
                                  Text(
                                    'Sync pending',
                                    style: AppTextStyles.badge.copyWith(color: AppColors.accentOrangeDark, fontSize: 10),
                                  ),
                                ]),
                              ),
                          ]),
                        ],
                      ),
                    ),
                  ),
                  // Chevron
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(Icons.chevron_right, color: AppColors.neutral400),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 12, color: AppColors.textMuted),
    const SizedBox(width: 3),
    Text(text, style: AppTextStyles.caption),
  ]);
}

// ─────────────────────────────────────────────────────────────
// SYNC QUEUE ITEM
// Individual row in the offline sync queue screen.
// ─────────────────────────────────────────────────────────────
class SyncQueueItem extends StatelessWidget {
  const SyncQueueItem({
    super.key,
    required this.name,
    required this.syncStatus,
    this.subtitle,
    this.progress,     // 0.0–1.0, shown only when syncing
    this.onRetry,
    this.icon,
  });

  final String name;
  final SyncStatus syncStatus;
  final String? subtitle;
  final double? progress;
  final VoidCallback? onRetry;
  final IconData? icon;

  Color get _bg => switch (syncStatus) {
    SyncStatus.synced  => AppColors.successGreenLight,
    SyncStatus.syncing => AppColors.primaryBlueLight,
    SyncStatus.failed  => AppColors.errorRedLight,
    SyncStatus.queued  => AppColors.neutral50,
  };

  Color get _border => switch (syncStatus) {
    SyncStatus.synced  => AppColors.successGreen.withValues(alpha: 0.3),
    SyncStatus.syncing => AppColors.primaryBlue.withValues(alpha: 0.3),
    SyncStatus.failed  => AppColors.errorRed.withValues(alpha: 0.3),
    SyncStatus.queued  => AppColors.neutral200,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md, vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: AppRadius.smAll,
        border: Border.all(color: _border),
      ),
      child: Row(children: [
        Icon(
          icon ?? Icons.file_upload_outlined,
          size: 20, color: syncStatus.color,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: AppTextStyles.labelSmall),
              if (subtitle != null)
                Text(subtitle!, style: AppTextStyles.caption.copyWith(fontSize: 11)),
              if (syncStatus == SyncStatus.syncing && progress != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: ClipRRect(
                    borderRadius: AppRadius.pillAll,
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      backgroundColor: AppColors.primaryBlue.withValues(alpha: 0.15),
                      valueColor: const AlwaysStoppedAnimation(AppColors.primaryBlue),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        if (syncStatus == SyncStatus.failed && onRetry != null)
          GestureDetector(
            onTap: onRetry,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.errorRed,
                borderRadius: AppRadius.pillAll,
              ),
              child: Text(
                'Retry',
                style: AppTextStyles.badge.copyWith(color: Colors.white),
              ),
            ),
          )
        else
          SyncStatusBadge(status: syncStatus),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SYNC QUEUE SECTION
// Titled group of SyncQueueItems with priority label.
// ─────────────────────────────────────────────────────────────
class SyncQueueSection extends StatelessWidget {
  const SyncQueueSection({
    super.key,
    required this.title,
    required this.priority,
    required this.items,
  });

  final String title;
  final int priority;
  final List<SyncQueueItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue,
              borderRadius: AppRadius.pillAll,
            ),
            child: Text(
              'P$priority',
              style: AppTextStyles.badge.copyWith(color: Colors.white, fontSize: 10),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(title, style: AppTextStyles.sectionHeader),
        ]),
        const SizedBox(height: AppSpacing.sm),
        ...items,
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// EMPTY STATE
// Friendly empty/error/offline state display.
// ─────────────────────────────────────────────────────────────
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
    this.actionLabel,
    this.fullScreen = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? action;
  final String? actionLabel;
  final bool fullScreen;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: AppColors.neutral300),
          const SizedBox(height: AppSpacing.lg),
          Text(title, style: AppTextStyles.displaySmall.copyWith(
            color: AppColors.textSecondary, fontSize: 18,
          ), textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.sm),
          Text(subtitle, style: AppTextStyles.bodySmall,
              textAlign: TextAlign.center),
          if (action != null && actionLabel != null) ...[
            const SizedBox(height: AppSpacing.xl),
            AppPrimaryButton(
              label: actionLabel!,
              onPressed: action,
              fullWidth: false,
            ),
          ],
        ],
      ),
    );

    return fullScreen
        ? SizedBox.expand(child: content)
        : content;
  }
}

// ─────────────────────────────────────────────────────────────
// CONFIRMATION HERO
// Used on End Trip / Delivery Complete screens.
// ─────────────────────────────────────────────────────────────
class ConfirmationHero extends StatelessWidget {
  const ConfirmationHero({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.bgColor = AppColors.successGreen,
    this.bgColorEnd,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color bgColor;
  final Color? bgColorEnd;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl, AppSpacing.xl2, AppSpacing.xl, AppSpacing.xl,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [bgColor, bgColorEnd ?? bgColor.withValues(alpha: 0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(children: [
        Icon(icon, size: 72, color: Colors.white.withValues(alpha: 0.9)),
        const SizedBox(height: AppSpacing.md),
        Text(
          title,
          style: AppTextStyles.displayMedium.copyWith(color: Colors.white),
          textAlign: TextAlign.center,
        ),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            subtitle!,
            style: AppTextStyles.bodySmall.copyWith(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
        ],
      ]),
    );
  }
}
