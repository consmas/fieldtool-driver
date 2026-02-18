// ============================================================
// ConsMas FieldTool Driver — Badge & Status Widgets
// ============================================================
// Widgets:
//   • TripStatusBadge     — en_route / arrived / completed etc.
//   • SyncStatusBadge     — queued / syncing / synced / failed
//   • OfflineBanner       — persistent offline mode strip
//   • AlertBanner         — info / success / warning / error
//   • PulseDot            — animated dot for live statuses
// ============================================================

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_spacing.dart';
import '../models/enums.dart';

// ─────────────────────────────────────────────────────────────
// PULSE DOT
// Animated pulsing indicator for live status.
// ─────────────────────────────────────────────────────────────
class PulseDot extends StatefulWidget {
  const PulseDot({
    super.key,
    this.color = AppColors.successGreen,
    this.size = 7,
  });
  final Color color;
  final double size;
  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _anim = Tween<double>(
      begin: 1.0,
      end: 0.4,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, child) => Opacity(opacity: _anim.value, child: child),
    child: Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    ),
  );
}

// ─────────────────────────────────────────────────────────────
// TRIP STATUS BADGE
// Icon + text + color — never color alone (WCAG 1.4.1).
// Usage:
//   TripStatusBadge(status: TripStatus.enRoute)
// ─────────────────────────────────────────────────────────────
class TripStatusBadge extends StatelessWidget {
  const TripStatusBadge({
    super.key,
    required this.status,
    this.compact = false,
  });
  final TripStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: status.badgeBg,
        borderRadius: AppRadius.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status.isLive)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: PulseDot(color: status.badgeFg, size: 6),
            )
          else ...[
            Icon(status.icon, size: 11, color: status.badgeFg),
            const SizedBox(width: 4),
          ],
          Text(
            status.label,
            style: AppTextStyles.badge.copyWith(color: status.badgeFg),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SYNC STATUS BADGE
// Inline, compact badge for media/status sync states.
// ─────────────────────────────────────────────────────────────
class SyncStatusBadge extends StatelessWidget {
  const SyncStatusBadge({super.key, required this.status});
  final SyncStatus status;

  @override
  Widget build(BuildContext context) {
    Widget leading;
    if (status == SyncStatus.syncing) {
      leading = SizedBox(
        width: 11,
        height: 11,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          valueColor: AlwaysStoppedAnimation(status.color),
        ),
      );
    } else {
      leading = Icon(status.icon, size: 12, color: status.color);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        leading,
        const SizedBox(width: 4),
        Text(
          status.label,
          style: AppTextStyles.badge.copyWith(
            color: status.color,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// OFFLINE BANNER
// Persistent strip shown at top when device is offline.
// Usage:
//   OfflineBanner(onRetry: _syncService.retry)
// ─────────────────────────────────────────────────────────────
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, this.onRetry, this.queueCount = 0});
  final VoidCallback? onRetry;
  final int queueCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        color: AppColors.errorRedLight,
        border: Border(bottom: BorderSide(color: AppColors.errorRed, width: 2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off, size: 14, color: AppColors.errorRed),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              queueCount > 0
                  ? 'Offline — $queueCount items saved locally'
                  : 'Offline — changes saved locally',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.errorRed,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (onRetry != null)
            GestureDetector(
              onTap: onRetry,
              child: Text(
                'RETRY',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.errorRed,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// ALERT BANNER
// Contextual message banner: info / success / warning / error.
// Usage:
//   AlertBanner(
//     type: AlertType.warning,
//     message: '1 item marked FAIL. Dispatch has been notified.',
//   )
// ─────────────────────────────────────────────────────────────
class AlertBanner extends StatelessWidget {
  const AlertBanner({
    super.key,
    required this.type,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.isDismissible = false,
    this.onDismiss,
  });

  final AlertType type;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool isDismissible;
  final VoidCallback? onDismiss;

  Color get _bg => switch (type) {
    AlertType.info => AppColors.primaryBlueLight,
    AlertType.success => AppColors.successGreenLight,
    AlertType.warning => AppColors.accentOrangeLight,
    AlertType.error => AppColors.errorRedLight,
  };

  Color get _fg => switch (type) {
    AlertType.info => AppColors.primaryBlueDark,
    AlertType.success => AppColors.successGreenDark,
    AlertType.warning => AppColors.accentOrangeDark,
    AlertType.error => AppColors.errorRed,
  };

  Color get _border => _fg.withValues(alpha: 0.25);

  IconData get _icon => switch (type) {
    AlertType.info => Icons.info_outline,
    AlertType.success => Icons.check_circle_outline,
    AlertType.warning => Icons.warning_amber_outlined,
    AlertType.error => Icons.error_outline,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: AppRadius.smAll,
        border: Border.all(color: _border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_icon, size: 16, color: _fg),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: _fg,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (actionLabel != null) ...[
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: onAction,
                    child: Text(
                      actionLabel!,
                      style: AppTextStyles.caption.copyWith(
                        color: _fg,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (isDismissible)
            GestureDetector(
              onTap: onDismiss,
              child: Icon(Icons.close, size: 16, color: _fg),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SAVE STATE INDICATOR
// Inline micro-feedback shown after saving: saved / syncing / synced / failed
// Usage:
//   SaveStateIndicator(state: SyncStatus.syncing)
// ─────────────────────────────────────────────────────────────
class SaveStateIndicator extends StatelessWidget {
  const SaveStateIndicator({
    super.key,
    required this.state,
    this.showLabel = true,
  });
  final SyncStatus state;
  final bool showLabel;

  String get _label => switch (state) {
    SyncStatus.queued => 'Saved locally',
    SyncStatus.syncing => 'Syncing…',
    SyncStatus.synced => 'Synced ✓',
    SyncStatus.failed => 'Sync failed',
  };

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SyncStatusBadge(status: state),
      if (showLabel) ...[
        const SizedBox(width: AppSpacing.xs),
        Text(_label, style: AppTextStyles.caption.copyWith(color: state.color)),
      ],
    ],
  );
}
