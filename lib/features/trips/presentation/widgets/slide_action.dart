import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/utils/app_theme.dart';

class SlideAction extends StatefulWidget {
  const SlideAction({
    super.key,
    required this.label,
    required this.onSubmit,
    this.enabled = true,
    this.completionThreshold = 0.85,
    this.enableHaptic = false,
  });

  final String label;
  final VoidCallback onSubmit;
  final bool enabled;
  final double completionThreshold;
  final bool enableHaptic;

  @override
  State<SlideAction> createState() => _SlideActionState();
}

class _SlideActionState extends State<SlideAction> {
  double _dragX = 0;
  bool _submitted = false;

  @override
  void didUpdateWidget(covariant SlideAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.label != widget.label ||
        oldWidget.enabled != widget.enabled) {
      _dragX = 0;
      _submitted = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final knobSize = 52.0;
        final maxDrag = (width - knobSize).clamp(0.0, width).toDouble();
        return Opacity(
          opacity: widget.enabled ? 1 : 0.5,
          child: GestureDetector(
            onHorizontalDragUpdate: widget.enabled
                ? (details) {
                    if (_submitted) return;
                    setState(() {
                      _dragX = (_dragX + details.delta.dx)
                          .clamp(0.0, maxDrag)
                          .toDouble();
                    });
                  }
                : null,
            onHorizontalDragEnd: widget.enabled
                ? (_) async {
                    if (_submitted) return;
                    final currentProgress = maxDrag == 0 ? 0 : _dragX / maxDrag;
                    if (currentProgress > widget.completionThreshold) {
                      _submitted = true;
                      if (widget.enableHaptic) {
                        HapticFeedback.mediumImpact();
                      }
                      widget.onSubmit();
                      setState(() => _dragX = maxDrag);
                    } else {
                      setState(() => _dragX = 0);
                    }
                  }
                : null,
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                color: const Color(0xFFF0F2F5),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: AppTheme.border, width: 1.5),
              ),
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Center(
                    child: Text(
                      widget.label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textMuted,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  Positioned(
                    left: _dragX,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppTheme.secondary,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.secondary.withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.arrow_forward,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
