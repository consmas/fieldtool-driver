import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/app_theme.dart';
import '../service/tracking_service.dart';

class TrackingStatusWidget extends ConsumerWidget {
  const TrackingStatusWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(trackingServiceProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: state.running
                    ? AppTheme.secondary.withValues(alpha: 0.15)
                    : AppTheme.textMuted.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                state.running ? Icons.location_on : Icons.location_off,
                color: state.running ? AppTheme.secondary : AppTheme.textMuted,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.running ? 'Tracking Active' : 'Tracking Off',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Last ping: ${state.lastPing?.toLocal().toString() ?? '—'}',
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
