import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class AxleLogomark extends StatelessWidget {
  const AxleLogomark({
    super.key,
    this.size = 64,
    this.color = AppColors.brandAmber,
    this.centerFillColor,
  });

  final double size;
  final Color color;
  final Color? centerFillColor;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _AxleLogomarkPainter(
        color: color,
        centerFillColor: centerFillColor ?? AppColors.brandDark,
      ),
    );
  }
}

class AxleWordmark extends StatelessWidget {
  const AxleWordmark({
    super.key,
    this.height = 28,
    this.color = AppColors.textPrimary,
  });

  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      'AXLE',
      style: TextStyle(
        fontSize: height,
        letterSpacing: 1.8,
        fontWeight: FontWeight.w800,
        color: color,
      ),
    );
  }
}

class AxleLogo extends StatelessWidget {
  const AxleLogo({
    super.key,
    this.size = 48,
    this.layout = Axis.horizontal,
    this.markColor = AppColors.brandAmber,
    this.textColor = AppColors.textPrimary,
  });

  final double size;
  final Axis layout;
  final Color markColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final wordHeight = size * 0.42;
    if (layout == Axis.vertical) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AxleLogomark(size: size, color: markColor),
          SizedBox(height: size * 0.22),
          AxleWordmark(height: wordHeight, color: textColor),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AxleLogomark(size: size, color: markColor),
        SizedBox(width: size * 0.28),
        AxleWordmark(height: wordHeight, color: textColor),
      ],
    );
  }
}

class _AxleLogomarkPainter extends CustomPainter {
  _AxleLogomarkPainter({
    required this.color,
    required this.centerFillColor,
  });

  final Color color;
  final Color centerFillColor;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = Offset(s / 2, s / 2);
    final outerR = s * 0.4375; // 28 / 64
    final nodeR = s * 0.086; // ~5.5 / 64
    final nodeInnerR = s * 0.039; // ~2.5 / 64
    final strokeOuter = s * 0.047; // 3 / 64
    final strokeMid = s * 0.04;

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    strokePaint.strokeWidth = strokeOuter;
    canvas.drawCircle(c, outerR, strokePaint);

    strokePaint.strokeWidth = strokeMid;
    canvas.drawLine(Offset(s * 0.0625, c.dy), Offset(s * 0.9375, c.dy), strokePaint);

    final leftNode = Offset(s * 0.28125, c.dy);
    final rightNode = Offset(s * 0.71875, c.dy);
    final fillPaint = Paint()..style = PaintingStyle.fill;

    fillPaint.color = color;
    canvas.drawCircle(leftNode, nodeR, fillPaint);
    canvas.drawCircle(rightNode, nodeR, fillPaint);

    fillPaint.color = centerFillColor;
    canvas.drawCircle(leftNode, nodeInnerR, fillPaint);
    canvas.drawCircle(rightNode, nodeInnerR, fillPaint);

    final routePaint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.031
      ..strokeCap = StrokeCap.round;
    final routePath = Path()
      ..moveTo(leftNode.dx, leftNode.dy)
      ..cubicTo(leftNode.dx, s * 0.25, rightNode.dx, s * 0.25, rightNode.dx, rightNode.dy);
    _drawDashedPath(canvas, routePath, routePaint, dash: s * 0.062, gap: s * 0.047);

    fillPaint.color = color.withValues(alpha: 0.85);
    canvas.drawCircle(Offset(c.dx, s * 0.289), s * 0.046, fillPaint);

    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.039
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final arrow = Path()
      ..moveTo(s * 0.4375, s * 0.086)
      ..lineTo(s * 0.5, s * 0.0156)
      ..lineTo(s * 0.5625, s * 0.086);
    canvas.drawPath(arrow, arrowPaint);
  }

  void _drawDashedPath(
    Canvas canvas,
    Path source,
    Paint paint, {
    required double dash,
    required double gap,
  }) {
    for (final metric in source.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final end = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AxleLogomarkPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.centerFillColor != centerFillColor;
  }
}
