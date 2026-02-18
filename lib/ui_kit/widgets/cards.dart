// ============================================================
// ConsMas FieldTool Driver — Card & Layout Widgets
// ============================================================
// Widgets:
//   • AppCard            — base styled card
//   • SectionCard        — card with overline title
//   • InfoRow            — key/value row inside cards
//   • StatBox            — metric display box (2-column grid)
//   • StatGrid           — 2×N grid of StatBox widgets
//   • TripProgressTracker— step-based progress (5 steps)
//   • OdometerDisplay    — monospace odometer readout
// ============================================================

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_spacing.dart';

// ─────────────────────────────────────────────────────────────
// APP CARD (base)
// ─────────────────────────────────────────────────────────────
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.borderColor,
    this.borderWidth = 1,
    this.accentColor,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? borderColor;
  final double borderWidth;

  /// Left accent stripe (colored border-left)
  final Color? accentColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Widget content = Container(
      padding: padding ?? AppSpacing.cardPaddingAll,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.lgAll,
        border: Border.all(
          color: borderColor ?? AppColors.neutral200,
          width: borderWidth,
        ),
        boxShadow: AppShadows.sm,
      ),
      child: child,
    );

    if (accentColor != null) {
      content = ClipRRect(
        borderRadius: AppRadius.lgAll,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: accentColor!, width: 4),
            ),
          ),
          child: content,
        ),
      );
    }

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        borderRadius: AppRadius.lgAll,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.lgAll,
          child: content,
        ),
      );
    }

    return content;
  }
}

// ─────────────────────────────────────────────────────────────
// SECTION CARD
// Card with an overline section title.
// Usage:
//   SectionCard(
//     title: 'Vehicle Exterior',
//     children: [...],
//   )
// ─────────────────────────────────────────────────────────────
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
    this.accentColor,
    this.onTap,
    this.padding,
    this.gap = AppSpacing.md,
  });

  final String title;
  final List<Widget> children;
  final Widget? trailing;
  final Color? accentColor;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      accentColor: accentColor,
      onTap: onTap,
      padding: padding ?? AppSpacing.cardPaddingAll,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                title.toUpperCase(),
                style: AppTextStyles.cardTitle,
              ),
            ),
            if (trailing != null) trailing!,
          ]),
          SizedBox(height: gap),
          ...children,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// INFO ROW
// Key/value display row inside a card.
// Usage:
//   InfoRow(label: 'Destination', value: 'Cape Town CBD')
//   InfoRow(label: 'Status', valueWidget: TripStatusBadge(...))
// ─────────────────────────────────────────────────────────────
class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.label,
    this.value,
    this.valueWidget,
    this.valueColor,
    this.showDivider = true,
    this.labelWidth = 110,
  }) : assert(
         value != null || valueWidget != null,
         'Provide either value or valueWidget',
       );

  final String label;
  final String? value;
  final Widget? valueWidget;
  final Color? valueColor;
  final bool showDivider;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: labelWidth,
                child: Text(label, style: AppTextStyles.caption),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: valueWidget ??
                    Text(
                      value!,
                      textAlign: TextAlign.end,
                      style: AppTextStyles.labelMedium.copyWith(
                        color: valueColor ?? AppColors.textPrimary,
                      ),
                    ),
              ),
            ],
          ),
        ),
        if (showDivider)
          const Divider(height: 0, thickness: 1, color: AppColors.neutral100),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// STAT BOX
// Single metric tile with label + value.
// ─────────────────────────────────────────────────────────────
class StatBox extends StatelessWidget {
  const StatBox({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.icon,
    this.subtitle,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final IconData? icon;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.neutral50,
        borderRadius: AppRadius.smAll,
        border: Border.all(color: AppColors.neutral200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: AppColors.textMuted),
              const SizedBox(width: 4),
            ],
            Text(label, style: AppTextStyles.caption),
          ]),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTextStyles.displaySmall.copyWith(
              fontSize: 18,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              style: AppTextStyles.caption.copyWith(fontSize: 10),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// STAT GRID
// Wraps StatBox widgets in a 2-column responsive grid.
// ─────────────────────────────────────────────────────────────
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.stats, this.columns = 2});
  final List<StatBox> stats;
  final int columns;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      crossAxisCount: columns,
      mainAxisSpacing: AppSpacing.sm,
      crossAxisSpacing: AppSpacing.sm,
      childAspectRatio: 1.6,
      children: stats,
    );
  }
}

// ─────────────────────────────────────────────────────────────
// TRIP PROGRESS TRACKER
// Horizontal stepper matching strict status progression.
// Usage:
//   TripProgressTracker(currentStep: 2) // 0-indexed
// ─────────────────────────────────────────────────────────────
class TripProgressTracker extends StatelessWidget {
  const TripProgressTracker({super.key, required this.currentStep});
  final int currentStep; // 0 = Checked, 1 = Loaded, 2 = En Route, 3 = Arrived, 4 = Done

  static const List<String> _labels = [
    'Checked', 'Loaded', 'En Route', 'Arrived', 'Done',
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(_labels.length * 2 - 1, (i) {
        if (i.isOdd) {
          // Connector line
          final stepIdx = i ~/ 2;
          final isDone = stepIdx < currentStep;
          return Expanded(
            child: Container(
              height: 2,
              color: isDone ? AppColors.successGreen : AppColors.neutral200,
            ),
          );
        }
        final stepIdx = i ~/ 2;
        final isDone = stepIdx < currentStep;
        final isActive = stepIdx == currentStep;
        return _StepNode(
          index: stepIdx,
          label: _labels[stepIdx],
          isDone: isDone,
          isActive: isActive,
        );
      }),
    );
  }
}

class _StepNode extends StatelessWidget {
  const _StepNode({
    required this.index,
    required this.label,
    required this.isDone,
    required this.isActive,
  });
  final int index;
  final String label;
  final bool isDone;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    Color bg, fg;
    if (isDone) {
      bg = AppColors.successGreen; fg = Colors.white;
    } else if (isActive) {
      bg = AppColors.primaryBlue; fg = Colors.white;
    } else {
      bg = AppColors.neutral200; fg = AppColors.textMuted;
    }

    return Column(mainAxisSize: MainAxisSize.min, children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 28, height: 28,
        decoration: BoxDecoration(
          color: bg, shape: BoxShape.circle,
          boxShadow: isActive ? AppShadows.bluePrimary : null,
        ),
        child: Center(
          child: isDone
              ? const Icon(Icons.check, color: Colors.white, size: 14)
              : Text(
                  '${index + 1}',
                  style: AppTextStyles.caption.copyWith(
                    color: fg, fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
      const SizedBox(height: 4),
      Text(
        label,
        style: AppTextStyles.caption.copyWith(fontSize: 10, color: fg == Colors.white ? AppColors.textSecondary : fg),
        textAlign: TextAlign.center,
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────
// ODOMETER DISPLAY
// Dark display card with monospace large digits.
// Usage:
//   OdometerDisplay(label: 'Current Reading', value: 142380)
// ─────────────────────────────────────────────────────────────
class OdometerDisplay extends StatelessWidget {
  const OdometerDisplay({
    super.key,
    required this.value,
    this.label = 'Odometer Reading',
    this.unit = 'kilometres',
    this.highlightColor = AppColors.accentOrange,
  });

  final int value;
  final String label;
  final String unit;
  final Color highlightColor;

  String get _formatted {
    final s = value.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.neutral900,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: AppColors.neutral700, width: 2),
      ),
      child: Column(children: [
        Text(
          label.toUpperCase(),
          style: AppTextStyles.overline.copyWith(
            color: AppColors.neutral500, letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(_formatted, style: AppTextStyles.monoLarge.copyWith(color: highlightColor)),
        const SizedBox(height: 4),
        Text(unit, style: AppTextStyles.caption.copyWith(color: AppColors.neutral500)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// FUEL LEVEL BAR
// Segmented visual fuel level indicator.
// ─────────────────────────────────────────────────────────────
class FuelLevelBar extends StatelessWidget {
  const FuelLevelBar({
    super.key,
    required this.level, // 0.0 – 1.0
    this.segments = 10,
    this.height = 40,
  });

  final double level;
  final int segments;
  final double height;

  @override
  Widget build(BuildContext context) {
    final filledCount = (level * segments).round().clamp(0, segments);
    return Row(
      children: List.generate(segments, (i) {
        final isFilled = i < filledCount;
        Color color = AppColors.neutral200;
        if (isFilled) {
          // Low = red, mid = orange, normal = green
          color = filledCount <= 3
              ? AppColors.errorRed
              : filledCount <= 5
                  ? AppColors.accentOrange
                  : AppColors.successGreen;
        }
        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            height: height * (0.4 + (i / segments) * 0.6),
            decoration: BoxDecoration(
              color: color,
              borderRadius: AppRadius.xsAll,
            ),
          ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SECTION HEADER
// Standalone section label above card groups.
// ─────────────────────────────────────────────────────────────
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key});
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm, top: AppSpacing.xs),
    child: Text(
      title.toUpperCase(),
      style: AppTextStyles.sectionHeader,
    ),
  );
}
