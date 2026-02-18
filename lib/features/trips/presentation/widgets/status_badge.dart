import 'package:flutter/material.dart';

import '../../../../core/utils/app_theme.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final String status;

  Color _colorForStatus() {
    switch (status) {
      case 'completed':
        return AppTheme.secondary;
      case 'en_route':
        return AppTheme.primary;
      case 'arrived':
      case 'offloaded':
      case 'loaded':
      case 'assigned':
        return AppTheme.accent;
      case 'cancelled':
        return Colors.redAccent;
      default:
        return Colors.blueGrey;
    }
  }

  Color _backgroundForStatus(Color color) {
    switch (status) {
      case 'completed':
        return AppTheme.successLight;
      case 'arrived':
      case 'offloaded':
      case 'loaded':
      case 'assigned':
        return AppTheme.warningLight;
      default:
        return color.withValues(alpha: 0.12);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorForStatus();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _backgroundForStatus(color),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.replaceAll('_', ' '),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
