// ============================================================
// ConsMas FieldTool Driver — Form & Input Widgets
// ============================================================
// Widgets:
//   • AppTextField          — labeled text input with states
//   • ChecklistItem         — pass/fail/skip item
//   • ChecklistSection      — grouped checklist card
//   • ToggleRow             — label + switch for toggles
//   • PhotoCaptureGrid      — 3-col photo evidence grid
//   • PhotoThumb            — individual photo slot
//   • SignaturePad          — drawing canvas for signatures
//   • ProgressBar           — labeled progress indicator
// ============================================================

import 'package:flutter/material.dart';
import '../models/enums.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_spacing.dart';
import 'cards.dart';

// ─────────────────────────────────────────────────────────────
// APP TEXT FIELD
// Labeled, with icon, validation error, and helper text.
// Usage:
//   AppTextField(
//     label: 'Driver ID',
//     hint: 'DRV-00001',
//     controller: _ctrl,
//     prefixIcon: Icons.badge_outlined,
//   )
// ─────────────────────────────────────────────────────────────
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.hint,
    this.controller,
    this.initialValue,
    this.keyboardType,
    this.obscureText = false,
    this.prefixIcon,
    this.suffixIcon,
    this.errorText,
    this.helperText,
    this.readOnly = false,
    this.onChanged,
    this.onTap,
    this.autofocus = false,
    this.maxLines = 1,
    this.minLines,
    this.enabled = true,
  });

  final String label;
  final String? hint;
  final TextEditingController? controller;
  final String? initialValue;
  final TextInputType? keyboardType;
  final bool obscureText;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final String? errorText;
  final String? helperText;
  final bool readOnly;
  final void Function(String)? onChanged;
  final VoidCallback? onTap;
  final bool autofocus;
  final int maxLines;
  final int? minLines;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.labelSmall),
        const SizedBox(height: AppSpacing.xs),
        TextFormField(
          controller: controller,
          initialValue: initialValue,
          keyboardType: keyboardType,
          obscureText: obscureText,
          readOnly: readOnly,
          onChanged: onChanged,
          onTap: onTap,
          autofocus: autofocus,
          maxLines: maxLines,
          minLines: minLines,
          enabled: enabled,
          style: AppTextStyles.bodyMedium,
          decoration: InputDecoration(
            hintText: hint,
            errorText: errorText,
            helperText: helperText,
            prefixIcon: prefixIcon != null
                ? Icon(prefixIcon, size: 20, color: AppColors.textMuted)
                : null,
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: readOnly ? AppColors.neutral100 : AppColors.neutral50,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// CHECKLIST ITEM
// PASS / FAIL / SKIP per item with tap cycling.
// Usage:
//   ChecklistItem(
//     label: 'Tyre pressure — all 18 wheels',
//     state: ChecklistItemState.passed,
//     onChanged: (s) => setState(() => _state = s),
//   )
// ─────────────────────────────────────────────────────────────
class ChecklistItem extends StatelessWidget {
  const ChecklistItem({
    super.key,
    required this.label,
    required this.state,
    required this.onChanged,
    this.failNote,
  });

  final String label;
  final ChecklistItemState state;
  final void Function(ChecklistItemState) onChanged;
  final String? failNote;

  void _cycle() {
    final next = switch (state) {
      ChecklistItemState.unchecked => ChecklistItemState.passed,
      ChecklistItemState.passed => ChecklistItemState.failed,
      ChecklistItemState.failed => ChecklistItemState.unchecked,
    };
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final isPassed = state == ChecklistItemState.passed;
    final isFailed = state == ChecklistItemState.failed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: _cycle,
          borderRadius: AppRadius.smAll,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Row(
              children: [
                // Checkbox visual
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: isPassed
                        ? AppColors.successGreen
                        : isFailed
                        ? AppColors.errorRed
                        : Colors.transparent,
                    borderRadius: AppRadius.xsAll,
                    border: Border.all(
                      color: isPassed
                          ? AppColors.successGreen
                          : isFailed
                          ? AppColors.errorRed
                          : AppColors.neutral300,
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: isPassed
                        ? const Icon(Icons.check, color: Colors.white, size: 14)
                        : isFailed
                        ? const Icon(Icons.close, color: Colors.white, size: 14)
                        : null,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    label,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: isPassed
                          ? AppColors.textMuted
                          : isFailed
                          ? AppColors.errorRed
                          : AppColors.textPrimary,
                      decoration: isPassed ? TextDecoration.lineThrough : null,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                // FAIL badge
                if (isFailed)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.errorRedLight,
                      borderRadius: AppRadius.pillAll,
                      border: Border.all(
                        color: AppColors.errorRed.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      'FAIL',
                      style: AppTextStyles.badge.copyWith(
                        color: AppColors.errorRed,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (isFailed && failNote != null)
          Padding(
            padding: const EdgeInsets.only(left: 36, bottom: 8),
            child: Text(
              '⚠ $failNote',
              style: AppTextStyles.caption.copyWith(color: AppColors.errorRed),
            ),
          ),
        const Divider(height: 0, color: AppColors.neutral100),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// CHECKLIST SECTION
// Grouped card of ChecklistItems with progress counter.
// ─────────────────────────────────────────────────────────────
class ChecklistSection extends StatelessWidget {
  const ChecklistSection({
    super.key,
    required this.title,
    required this.items,
    required this.onItemChanged,
  });

  final String title;
  final List<({String label, ChecklistItemState state, String? failNote})>
  items;
  final void Function(int index, ChecklistItemState state) onItemChanged;

  int get _passedCount =>
      items.where((i) => i.state == ChecklistItemState.passed).length;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: title,
      trailing: Text(
        '$_passedCount/${items.length}',
        style: AppTextStyles.labelSmall.copyWith(color: AppColors.successGreen),
      ),
      children: List.generate(items.length, (i) {
        final item = items[i];
        return ChecklistItem(
          label: item.label,
          state: item.state,
          failNote: item.failNote,
          onChanged: (s) => onItemChanged(i, s),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// TOGGLE ROW
// Full-row tappable label + switch, 52px min height.
// Usage:
//   ToggleRow(
//     label: 'All pallets offloaded',
//     value: _offloaded,
//     onChanged: (v) => setState(() => _offloaded = v),
//   )
// ─────────────────────────────────────────────────────────────
class ToggleRow extends StatelessWidget {
  const ToggleRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.showDivider = true,
    this.enabled = true,
  });

  final String label;
  final bool value;
  final void Function(bool) onChanged;
  final String? subtitle;
  final bool showDivider;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: enabled ? () => onChanged(!value) : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppTouchTargets.toggleRow,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: AppTextStyles.labelMedium),
                      if (subtitle != null)
                        Text(subtitle!, style: AppTextStyles.caption),
                    ],
                  ),
                ),
                Switch(value: value, onChanged: enabled ? onChanged : null),
              ],
            ),
          ),
        ),
        if (showDivider) const Divider(height: 0, color: AppColors.neutral100),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// PHOTO THUMB
// Single photo slot — empty, captured, or uploading.
// ─────────────────────────────────────────────────────────────
class PhotoThumb extends StatelessWidget {
  const PhotoThumb({
    super.key,
    this.imageProvider,
    this.onTap,
    this.isRequired = false,
    this.syncStatus,
    this.showAddButton = false,
  });

  final ImageProvider? imageProvider;
  final VoidCallback? onTap;
  final bool isRequired;
  final SyncStatus? syncStatus;
  final bool showAddButton;

  bool get _isCaptured => imageProvider != null;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: showAddButton
                ? Colors.transparent
                : AppColors.primaryBlueLight,
            borderRadius: AppRadius.smAll,
            border: showAddButton
                ? Border.all(
                    color: AppColors.neutral300,
                    width: 2,
                    style: BorderStyle.solid,
                  )
                : Border.all(
                    color: AppColors.primaryBlue.withValues(alpha: 0.2),
                  ),
            image: _isCaptured
                ? DecorationImage(image: imageProvider!, fit: BoxFit.cover)
                : null,
          ),
          child: Stack(
            children: [
              if (showAddButton)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 28,
                        color: AppColors.neutral400,
                      ),
                    ],
                  ),
                )
              else if (!_isCaptured)
                Center(
                  child: Icon(
                    Icons.image_outlined,
                    size: 28,
                    color: AppColors.primaryBlueMid,
                  ),
                ),
              // Sync status overlay
              if (_isCaptured && syncStatus != null)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: syncStatus!.color,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      syncStatus!.icon,
                      color: Colors.white,
                      size: 11,
                    ),
                  ),
                ),
              // Required star
              if (isRequired && !_isCaptured)
                const Positioned(
                  top: 4,
                  left: 4,
                  child: Text(
                    '★',
                    style: TextStyle(color: AppColors.errorRed, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// PHOTO CAPTURE GRID
// 3-column grid of photo slots with an "Add" placeholder.
// Usage:
//   PhotoCaptureGrid(
//     photos: _photos, // List<CapturedPhoto>
//     requiredCount: 3,
//     onAddPhoto: _openCamera,
//     onTapPhoto: _viewPhoto,
//   )
// ─────────────────────────────────────────────────────────────
class PhotoCaptureGrid extends StatelessWidget {
  const PhotoCaptureGrid({
    super.key,
    required this.capturedCount,
    required this.requiredCount,
    this.onAddPhoto,
    this.syncStatuses = const [],
    this.columns = 3,
  });

  final int capturedCount;
  final int requiredCount;
  final VoidCallback? onAddPhoto;
  final List<SyncStatus> syncStatuses;
  final int columns;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.count(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          crossAxisCount: columns,
          crossAxisSpacing: AppSpacing.sm,
          mainAxisSpacing: AppSpacing.sm,
          children: [
            ...List.generate(
              capturedCount,
              (i) => PhotoThumb(
                imageProvider:
                    null, // Pass real ImageProvider in actual implementation
                syncStatus: i < syncStatuses.length
                    ? syncStatuses[i]
                    : SyncStatus.synced,
              ),
            ),
            PhotoThumb(showAddButton: true, onTap: onAddPhoto),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: '$capturedCount ',
                style: AppTextStyles.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  color: capturedCount >= requiredCount
                      ? AppColors.successGreen
                      : AppColors.textPrimary,
                ),
              ),
              TextSpan(
                text: 'of $requiredCount required photos captured',
                style: AppTextStyles.caption,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// PROGRESS BAR
// Labeled progress indicator with percentage.
// ─────────────────────────────────────────────────────────────
class AppProgressBar extends StatelessWidget {
  const AppProgressBar({
    super.key,
    required this.value, // 0.0 – 1.0
    this.label,
    this.valueLabel,
    this.color = AppColors.primaryBlue,
    this.height = 6,
    this.showLabels = true,
  });

  final double value;
  final String? label;
  final String? valueLabel;
  final Color color;
  final double height;
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showLabels && (label != null || valueLabel != null))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (label != null) Text(label!, style: AppTextStyles.caption),
                if (valueLabel != null)
                  Text(
                    valueLabel!,
                    style: AppTextStyles.caption.copyWith(
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
              ],
            ),
          ),
        ClipRRect(
          borderRadius: AppRadius.pillAll,
          child: LinearProgressIndicator(
            value: value,
            backgroundColor: AppColors.neutral200,
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: height,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SIGNATURE PAD
// Canvas for capturing handwritten signatures.
// Usage:
//   SignaturePad(
//     controller: _sigCtrl,
//     onSigned: () => setState(() => _hasSig = true),
//   )
// In actual implementation, use syncfusion_flutter_signaturepad
// or a custom CustomPainter-based approach.
// ─────────────────────────────────────────────────────────────
class SignaturePadPlaceholder extends StatefulWidget {
  const SignaturePadPlaceholder({super.key, this.onSigned, this.height = 100});

  final VoidCallback? onSigned;
  final double height;

  @override
  State<SignaturePadPlaceholder> createState() =>
      _SignaturePadPlaceholderState();
}

class _SignaturePadPlaceholderState extends State<SignaturePadPlaceholder> {
  final List<List<Offset>> _strokes = [];
  List<Offset> _currentStroke = [];
  bool _hasSigned = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onPanStart: (d) {
            setState(() {
              _currentStroke = [d.localPosition];
              _strokes.add(_currentStroke);
            });
          },
          onPanUpdate: (d) {
            setState(() {
              _currentStroke.add(d.localPosition);
              if (!_hasSigned) {
                _hasSigned = true;
                widget.onSigned?.call();
              }
            });
          },
          child: Container(
            height: widget.height,
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(
                color: _hasSigned
                    ? AppColors.successGreen
                    : AppColors.neutral300,
                width: 2,
                style: BorderStyle.solid,
              ),
              borderRadius: AppRadius.smAll,
              color: AppColors.neutral50,
            ),
            child: CustomPaint(
              painter: _SignaturePainter(_strokes),
              child: _hasSigned
                  ? null
                  : Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.edit,
                            size: 16,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Sign here',
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
        if (_hasSigned)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '✓ Signature captured',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.successGreen,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() {
                    _strokes.clear();
                    _hasSigned = false;
                  }),
                  child: Text(
                    'Clear',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textMuted,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter(this.strokes);
  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.neutral800
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (int i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_SignaturePainter old) => old.strokes != strokes;
}
