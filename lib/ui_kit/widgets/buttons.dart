// ============================================================
// ConsMas FieldTool Driver — Button Widgets
// ============================================================
// Widgets:
//   • AppPrimaryButton       — full-width, 52px, 4 color variants
//   • AppSecondaryButton     — full-width outlined
//   • AppIconButton          — 44×44 square icon button
//   • AppQuickActionButton   — icon + label grid button
//   • SlideToConfirmButton   — drag-to-activate for critical actions
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_spacing.dart';

// ── Enums ──────────────────────────────────────────────────────
enum PrimaryButtonVariant { blue, green, orange, red, dark }
enum LoadingButtonState { idle, loading, success, error }

// ─────────────────────────────────────────────────────────────
// PRIMARY BUTTON
// Full-width, 52px tall, with loading/success/error states.
// Usage:
//   AppPrimaryButton(
//     label: 'Mark as Arrived',
//     onPressed: _handleArrived,
//     variant: PrimaryButtonVariant.green,
//     state: _buttonState,
//   )
// ─────────────────────────────────────────────────────────────
class AppPrimaryButton extends StatelessWidget {
  const AppPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = PrimaryButtonVariant.blue,
    this.state = LoadingButtonState.idle,
    this.leadingIcon,
    this.subtitle,
    this.fullWidth = true,
    this.height = AppTouchTargets.btnPrimary,
  });

  final String label;
  final VoidCallback? onPressed;
  final PrimaryButtonVariant variant;
  final LoadingButtonState state;
  final IconData? leadingIcon;
  final String? subtitle;
  final bool fullWidth;
  final double height;

  Color get _bgColor => switch (variant) {
    PrimaryButtonVariant.blue   => AppColors.primaryBlue,
    PrimaryButtonVariant.green  => AppColors.successGreen,
    PrimaryButtonVariant.orange => AppColors.accentOrange,
    PrimaryButtonVariant.red    => AppColors.errorRed,
    PrimaryButtonVariant.dark   => AppColors.neutral800,
  };

  Color get _fgColor => variant == PrimaryButtonVariant.orange
      ? AppColors.neutral800
      : AppColors.textOnPrimary;

  List<BoxShadow> get _shadow => switch (variant) {
    PrimaryButtonVariant.blue   => AppShadows.bluePrimary,
    PrimaryButtonVariant.green  => AppShadows.greenSuccess,
    PrimaryButtonVariant.orange => AppShadows.orangeAccent,
    _                           => AppShadows.sm,
  };

  bool get _isDisabled => onPressed == null || state == LoadingButtonState.loading;

  @override
  Widget build(BuildContext context) {
    final effectiveBg = state == LoadingButtonState.success
        ? AppColors.successGreen
        : state == LoadingButtonState.error
            ? AppColors.errorRed
            : _bgColor;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: fullWidth ? double.infinity : null,
      height: height,
      decoration: BoxDecoration(
        color: _isDisabled ? effectiveBg.withValues(alpha: 0.45) : effectiveBg,
        borderRadius: AppRadius.mdAll,
        boxShadow: _isDisabled ? [] : _shadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadius.mdAll,
        child: InkWell(
          onTap: _isDisabled ? null : onPressed,
          borderRadius: AppRadius.mdAll,
          splashColor: Colors.white24,
          highlightColor: Colors.white12,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: _buildContent(effectiveBg),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(Color bg) {
    if (state == LoadingButtonState.loading) {
      return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        SizedBox(
          width: 20, height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation(_fgColor),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text('Please wait…', style: AppTextStyles.buttonPrimary.copyWith(color: _fgColor)),
      ]);
    }

    if (state == LoadingButtonState.success) {
      return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.check_circle, color: _fgColor, size: 20),
        const SizedBox(width: AppSpacing.sm),
        Text('Done!', style: AppTextStyles.buttonPrimary.copyWith(color: _fgColor)),
      ]);
    }

    if (subtitle != null) {
      return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(label, style: AppTextStyles.buttonPrimary.copyWith(color: _fgColor)),
        Text(
          subtitle!,
          style: AppTextStyles.caption.copyWith(color: _fgColor.withValues(alpha: 0.8)),
        ),
      ]);
    }

    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      if (leadingIcon != null) ...[
        Icon(leadingIcon, color: _fgColor, size: 20),
        const SizedBox(width: AppSpacing.sm),
      ],
      Text(label, style: AppTextStyles.buttonPrimary.copyWith(color: _fgColor)),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────
// SECONDARY BUTTON
// Outlined, 48px, primary blue border.
// ─────────────────────────────────────────────────────────────
class AppSecondaryButton extends StatelessWidget {
  const AppSecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.leadingIcon,
    this.fullWidth = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? leadingIcon;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: fullWidth ? double.infinity : null,
      height: AppTouchTargets.btnSecondary,
      child: OutlinedButton(
        onPressed: onPressed,
        style: fullWidth
            ? null
            : OutlinedButton.styleFrom(
                minimumSize: const Size(0, AppTouchTargets.btnSecondary),
              ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (leadingIcon != null) ...[
            Icon(leadingIcon, size: 18),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(label),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// ICON BUTTON
// 44×44 square with rounded corners and a tinted background.
// ─────────────────────────────────────────────────────────────
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.bgColor,
    this.iconColor,
    this.size = 44,
    this.iconSize = 20,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final Color? bgColor;
  final Color? iconColor;
  final double size;
  final double iconSize;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final bg = bgColor ?? AppColors.primaryBlueLight;
    final fg = iconColor ?? AppColors.primaryBlue;
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: bg,
        borderRadius: AppRadius.smAll,
        child: InkWell(
          onTap: onPressed,
          borderRadius: AppRadius.smAll,
          child: SizedBox(
            width: size, height: size,
            child: Icon(icon, color: fg, size: iconSize),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// QUICK ACTION BUTTON
// Used in Trip Detail summary strip: icon + label in a card.
// ─────────────────────────────────────────────────────────────
class QuickActionButton extends StatelessWidget {
  const QuickActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.onDark = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final bg = onDark
        ? Colors.white.withValues(alpha: 0.10)
        : AppColors.neutral50;
    final border = onDark
        ? Colors.white.withValues(alpha: 0.18)
        : AppColors.neutral200;
    final fg = onDark ? Colors.white70 : AppColors.textMuted;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: AppRadius.smAll,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs, vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: AppRadius.smAll,
            border: Border.all(color: border),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 22, color: fg),
            const SizedBox(height: 4),
            Text(
              label, textAlign: TextAlign.center,
              style: AppTextStyles.caption.copyWith(
                color: fg, fontWeight: FontWeight.w600, fontSize: 10,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SLIDE TO CONFIRM BUTTON
// Drag-to-activate widget for irreversible actions.
// Usage:
//   SlideToConfirmButton(
//     label: 'SLIDE TO START TRIP',
//     thumbIcon: Icons.local_shipping,
//     thumbColor: AppColors.successGreen,
//     onConfirmed: _startTrip,
//   )
// ─────────────────────────────────────────────────────────────
class SlideToConfirmButton extends StatefulWidget {
  const SlideToConfirmButton({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.thumbIcon = Icons.chevron_right,
    this.thumbColor = AppColors.successGreen,
    this.labelColor,
    this.height = 60,
    this.thumbSize = 56,
    this.activationThreshold = 0.80,
  });

  final String label;
  final VoidCallback onConfirmed;
  final IconData thumbIcon;
  final Color thumbColor;
  final Color? labelColor;
  final double height;
  final double thumbSize;
  /// How far (0–1) the thumb must travel before triggering.
  final double activationThreshold;

  @override
  State<SlideToConfirmButton> createState() => _SlideToConfirmButtonState();
}

class _SlideToConfirmButtonState extends State<SlideToConfirmButton>
    with SingleTickerProviderStateMixin {
  double _dragX = 0;
  bool _confirmed = false;
  late AnimationController _snapController;
  late Animation<double> _snapAnimation;
  double _maxDrag = 0;

  @override
  void initState() {
    super.initState();
    _snapController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _snapController.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_confirmed) return;
    setState(() {
      _dragX = (_dragX + d.delta.dx).clamp(0, _maxDrag);
    });
  }

  void _onDragEnd(DragEndDetails _) {
    if (_confirmed) return;
    final progress = _dragX / _maxDrag;
    if (progress >= widget.activationThreshold) {
      setState(() { _confirmed = true; _dragX = _maxDrag; });
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 400), widget.onConfirmed);
    } else {
      _snapAnimation = Tween<double>(begin: _dragX, end: 0).animate(
        CurvedAnimation(parent: _snapController, curve: Curves.easeOut),
      )..addListener(() => setState(() { _dragX = _snapAnimation.value; }));
      _snapController.forward(from: 0);
      HapticFeedback.lightImpact();
    }
  }

  void reset() {
    setState(() { _dragX = 0; _confirmed = false; });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      _maxDrag = constraints.maxWidth - widget.thumbSize - 4;
      final progress = _dragX / (_maxDrag == 0 ? 1 : _maxDrag);

      return Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: AppColors.neutral100,
          borderRadius: BorderRadius.circular(widget.height / 2),
          border: Border.all(color: AppColors.neutral200, width: 1.5),
        ),
        child: Stack(alignment: Alignment.centerLeft, children: [
          // Fill track
          AnimatedContainer(
            duration: const Duration(milliseconds: 50),
            width: _dragX + widget.thumbSize,
            height: widget.height,
            decoration: BoxDecoration(
              color: widget.thumbColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(widget.height / 2),
            ),
          ),
          // Label (fades as thumb advances)
          Center(
            child: AnimatedOpacity(
              opacity: (1 - progress * 2).clamp(0, 1),
              duration: const Duration(milliseconds: 100),
              child: Text(
                widget.label,
                style: AppTextStyles.labelSmall.copyWith(
                  color: widget.labelColor ?? AppColors.textMuted,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
          // Thumb
          Positioned(
            left: _dragX + 2,
            child: GestureDetector(
              onHorizontalDragUpdate: _onDragUpdate,
              onHorizontalDragEnd: _onDragEnd,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                width: widget.thumbSize,
                height: widget.thumbSize,
                decoration: BoxDecoration(
                  color: _confirmed ? widget.thumbColor : widget.thumbColor,
                  shape: BoxShape.circle,
                  boxShadow: AppShadows.greenSuccess,
                ),
                child: Icon(
                  _confirmed ? Icons.check : widget.thumbIcon,
                  color: Colors.white,
                  size: 26,
                ),
              ),
            ),
          ),
        ]),
      );
    });
  }
}
