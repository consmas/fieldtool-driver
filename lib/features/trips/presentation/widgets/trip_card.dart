import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/app_theme.dart';
import '../../domain/trip.dart';
import 'status_badge.dart';

class TripCard extends StatelessWidget {
  const TripCard({super.key, required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.go('/trips/${trip.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.local_shipping, color: AppTheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Trip #${trip.id}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      (() {
                        final route = [trip.pickupLocation, trip.dropoffLocation]
                            .whereType<String>()
                            .where((e) => e.trim().isNotEmpty)
                            .join(' → ');
                        if (route.isNotEmpty) return route;
                        return trip.destination ?? 'Destination pending';
                      })(),
                      style: const TextStyle(color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
              StatusBadge(status: trip.status),
            ],
          ),
        ),
      ),
    );
  }
}
