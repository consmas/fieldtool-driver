import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/logger.dart';
import '../../../ui_kit/models/enums.dart' as kit_enums;
import '../../../ui_kit/theme/app_colors.dart';
import '../../../ui_kit/theme/app_spacing.dart';
import '../../../ui_kit/widgets/buttons.dart';
import '../../../ui_kit/widgets/cards.dart';
import '../../../ui_kit/widgets/navigation.dart' as kit_nav;
import '../../evidence/presentation/capture_evidence_page.dart';
import '../../tracking/service/tracking_service.dart';
import '../data/trips_repository.dart';
import '../domain/trip.dart';
import '../domain/trip_stop.dart';
import 'delivery_completion_page.dart';
import 'fuel_post_trip_page.dart';
import 'live_tracking_page.dart';
import 'load_details_page.dart';
import 'attachments_viewer_page.dart';
import 'pre_trip_form_page.dart';
import 'start_trip_page.dart';

final tripDetailProvider = FutureProvider.family<Trip, int>((ref, id) {
  return ref.read(tripsRepositoryProvider).fetchTrip(id);
});

final tripStopsProvider = FutureProvider.family<List<TripStop>, int>((
  ref,
  id,
) async {
  try {
    return await ref.read(tripsRepositoryProvider).fetchTripStops(id);
  } catch (_) {
    return [];
  }
});

final preTripProvider = FutureProvider.family<Map<String, dynamic>?, int>((
  ref,
  id,
) async {
  return ref.read(tripsRepositoryProvider).fetchPreTrip(id);
});

class TripDetailPage extends ConsumerWidget {
  const TripDetailPage({super.key, required this.tripId});

  final int tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripAsync = ref.watch(tripDetailProvider(tripId));
    final stopsAsync = ref.watch(tripStopsProvider(tripId));
    final preTripAsync = ref.watch(preTripProvider(tripId));

    Future<void> refreshTripData() async {
      await Future.wait([
        ref.refresh(tripDetailProvider(tripId).future),
        ref.refresh(preTripProvider(tripId).future),
        ref.refresh(tripStopsProvider(tripId).future),
      ]);
    }

    return Scaffold(
      body: tripAsync.when(
        data: (trip) {
          final stops = stopsAsync.maybeWhen(
            data: (value) => value,
            orElse: () => <TripStop>[],
          );
          final preTrip = preTripAsync.maybeWhen(
            data: (value) => value,
            orElse: () => null,
          );

          final summaryStatus = _mapTripStatus(trip.status);
          final progressStep = _progressStepForStatus(trip.status);
          final allStopsCompleted =
              stops.isEmpty || stops.every((s) => s.arrivalTimeAtSite != null);
          final canCompleteTrip = allStopsCompleted && trip.hasOdometerEnd;
          final primaryLabel = _primaryCtaLabel(trip.status, canCompleteTrip);

          Future<void> openPreTrip() async {
            final result = await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (_) => PreTripFormPage(tripId: trip.id),
              ),
            );
            if (result == true) await refreshTripData();
          }

          Future<void> openLoadDetails() async {
            final result = await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (_) => LoadDetailsPage(tripId: trip.id),
              ),
            );
            if (result == true) await refreshTripData();
          }

          Future<void> openEvidence() async {
            final result = await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (_) => CaptureEvidencePage(tripId: trip.id),
              ),
            );
            if (result == true) await refreshTripData();
          }

          Future<void> callDispatch() async {
            final contact =
                trip.customerContactPhone ?? trip.driverContact ?? 'N/A';
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Dispatch contact: $contact')),
            );
          }

          Future<void> runPrimaryAction() async {
            try {
              final repo = ref.read(tripsRepositoryProvider);
              switch (trip.status) {
                case 'assigned':
                case 'loaded':
                case 'draft':
                case 'scheduled':
                  final started = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StartTripPage(tripId: trip.id),
                    ),
                  );
                  if (started == true) await refreshTripData();
                  return;
                case 'en_route':
                  await repo.updateStatus(trip.id, 'arrived');
                  await refreshTripData();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Trip marked as arrived.')),
                  );
                  return;
                case 'arrived':
                  await Navigator.push<Map<String, dynamic>?>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DeliveryCompletionPage(tripId: trip.id),
                    ),
                  );
                  await refreshTripData();
                  return;
                case 'offloaded':
                  if (!canCompleteTrip) {
                    await Navigator.push<String?>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FuelPostTripPage(tripId: trip.id),
                      ),
                    );
                    await refreshTripData();
                    return;
                  }
                  await ref
                      .read(trackingServiceProvider.notifier)
                      .stopTracking();
                  await repo.updateStatus(trip.id, 'completed');
                  await refreshTripData();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Trip completed.')),
                  );
                  return;
                case 'completed':
                  await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LiveTrackingPage(tripId: trip.id),
                    ),
                  );
                  return;
                default:
                  return;
              }
            } catch (e, st) {
              Logger.e('Trip primary action failed', e, st);
              if (!context.mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Action failed: $e')));
            }
          }

          return Stack(
            children: [
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFF2F7FF), Color(0xFFFFFFFF)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
              SafeArea(
                child: kit_nav.StickyBottomBar(
                  bottomBar: kit_nav.BottomActionBar(
                    primary: AppPrimaryButton(
                      label: primaryLabel,
                      leadingIcon: _primaryCtaIcon(trip.status),
                      variant: _primaryCtaVariant(trip.status),
                      onPressed: runPrimaryAction,
                    ),
                  ),
                  child: RefreshIndicator(
                    onRefresh: refreshTripData,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverAppBar(
                          pinned: true,
                          floating: false,
                          expandedHeight: 0,
                          backgroundColor: AppColors.primaryBlue,
                          title: Text(trip.referenceCode),
                          actions: [
                            PopupMenuButton<String>(
                              icon: const Icon(
                                Icons.more_vert,
                                color: Colors.white,
                              ),
                              onSelected: (value) async {
                                switch (value) {
                                  case 'history':
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Trip history coming soon.',
                                        ),
                                      ),
                                    );
                                    break;
                                  case 'issue':
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Issue report drafted.'),
                                      ),
                                    );
                                    break;
                                  case 'dispatch':
                                    await callDispatch();
                                    break;
                                  case 'docs':
                                    await Navigator.push<void>(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => AttachmentsViewerPage(
                                          tripId: trip.id,
                                        ),
                                      ),
                                    );
                                    break;
                                }
                              },
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                  value: 'history',
                                  child: Text('View trip history'),
                                ),
                                PopupMenuItem(
                                  value: 'issue',
                                  child: Text('Report issue'),
                                ),
                                PopupMenuItem(
                                  value: 'dispatch',
                                  child: Text('Contact dispatch'),
                                ),
                                PopupMenuItem(
                                  value: 'docs',
                                  child: Text('Trip documents'),
                                ),
                              ],
                            ),
                          ],
                        ),
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: _SummaryStripDelegate(
                            child: kit_nav.TripSummaryStrip(
                              destination:
                                  trip.destination ??
                                  trip.dropoffLocation ??
                                  'Destination pending',
                              waybill: trip.waybillNumber ?? trip.referenceCode,
                              eta: _etaText(trip),
                              distanceRemaining: trip.distanceKm == null
                                  ? '—'
                                  : '${trip.distanceKm!.toStringAsFixed(1)} km',
                              status: summaryStatus,
                              lastUpdated: 'just now',
                              quickActions: [
                                (
                                  icon: Icons.assignment_outlined,
                                  label: 'Checklist',
                                  onTap: openPreTrip,
                                ),
                                (
                                  icon: Icons.inventory_2_outlined,
                                  label: 'Load',
                                  onTap: openLoadDetails,
                                ),
                                (
                                  icon: Icons.camera_alt_outlined,
                                  label: 'Evidence',
                                  onTap: openEvidence,
                                ),
                                (
                                  icon: Icons.support_agent_outlined,
                                  label: 'Dispatch',
                                  onTap: callDispatch,
                                ),
                              ],
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SectionCard(
                                  title: 'Trip Progress',
                                  children: [
                                    TripProgressTracker(
                                      currentStep: progressStep,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.md),
                                SectionCard(
                                  title: 'Live Stats',
                                  children: [
                                    StatGrid(
                                      stats: [
                                        StatBox(
                                          label: 'Speed',
                                          value:
                                              trip.latestLocationSpeedKph ==
                                                  null
                                              ? '—'
                                              : '${trip.latestLocationSpeedKph!.toStringAsFixed(0)} km/h',
                                          icon: Icons.speed,
                                          valueColor: AppColors.primaryBlue,
                                        ),
                                        StatBox(
                                          label: 'Odometer',
                                          value: trip.odometerEndKm != null
                                              ? '${trip.odometerEndKm!.toStringAsFixed(1)} km'
                                              : (trip.odometerStartKm != null
                                                    ? '${trip.odometerStartKm!.toStringAsFixed(1)} km'
                                                    : '—'),
                                          icon: Icons.pin,
                                          valueColor:
                                              AppColors.accentOrangeDark,
                                        ),
                                        StatBox(
                                          label: 'Photos',
                                          value: _photosProgressText(
                                            trip,
                                            preTrip,
                                          ),
                                          icon: Icons.photo_library_outlined,
                                          valueColor: AppColors.successGreen,
                                        ),
                                        StatBox(
                                          label: 'Fuel',
                                          value:
                                              trip.fuelLitresFilled == null ||
                                                  trip.fuelLitresFilled!.isEmpty
                                              ? '—'
                                              : '${trip.fuelLitresFilled} L',
                                          icon:
                                              Icons.local_gas_station_outlined,
                                          valueColor:
                                              AppColors.accentOrangeDark,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.md),
                                SectionCard(
                                  title: 'Delivery Point Details',
                                  children: [
                                    InfoRow(
                                      label: 'Client',
                                      value: trip.clientName ?? '—',
                                    ),
                                    InfoRow(
                                      label: 'Destination',
                                      value:
                                          trip.destination ??
                                          trip.dropoffLocation ??
                                          '—',
                                    ),
                                    InfoRow(
                                      label: 'Delivery Address',
                                      value: trip.deliveryAddress ?? '—',
                                    ),
                                    InfoRow(
                                      label: 'Contact',
                                      value: _deliveryContact(trip),
                                    ),
                                    InfoRow(
                                      label: 'Waybill',
                                      value:
                                          trip.waybillNumber ??
                                          trip.referenceCode,
                                    ),
                                    InfoRow(
                                      label: 'ETA',
                                      value: _etaText(trip),
                                      showDivider: false,
                                    ),
                                  ],
                                ),
                                if (stops.isNotEmpty) ...[
                                  const SizedBox(height: AppSpacing.md),
                                  SectionCard(
                                    title: 'Stops',
                                    children: [
                                      for (final stop in stops) ...[
                                        InfoRow(
                                          label: 'Stop ${stop.id}',
                                          value:
                                              stop.destination ??
                                              stop.deliveryAddress ??
                                              '—',
                                        ),
                                        AppSecondaryButton(
                                          label: 'Complete Stop',
                                          fullWidth: false,
                                          onPressed: () async {
                                            final result =
                                                await Navigator.push<bool>(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        DeliveryCompletionPage(
                                                          tripId: trip.id,
                                                          stop: stop,
                                                        ),
                                                  ),
                                                );
                                            if (result == true) {
                                              ref.invalidate(
                                                tripStopsProvider(trip.id),
                                              );
                                              await refreshTripData();
                                            }
                                          },
                                        ),
                                        const SizedBox(height: AppSpacing.sm),
                                      ],
                                    ],
                                  ),
                                ],
                                const SizedBox(height: AppSpacing.md),
                                SectionCard(
                                  title: 'Attachments',
                                  children: [
                                    AppSecondaryButton(
                                      label: 'Open Attachments Viewer',
                                      leadingIcon: Icons.attach_file,
                                      onPressed: () async {
                                        await Navigator.push<void>(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                AttachmentsViewerPage(
                                                  tripId: trip.id,
                                                ),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.xl),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Failed to load trip: $error')),
      ),
    );
  }

  static String _etaText(Trip trip) {
    final eta = trip.estimatedArrivalTime;
    if (eta == null) return '—';
    final localEta = eta.toLocal();
    final time =
        '${localEta.hour.toString().padLeft(2, '0')}:${localEta.minute.toString().padLeft(2, '0')}';
    return '$time (${_durationFromNow(localEta)})';
  }

  static String _photosProgressText(Trip trip, Map<String, dynamic>? preTrip) {
    final count = _photoCount(trip, preTrip);
    const requiredCount = 6;
    if (count >= requiredCount) return '$count / $requiredCount ✓';
    return '$count / $requiredCount';
  }

  static int _photoCount(Trip trip, Map<String, dynamic>? preTrip) {
    var count = 0;
    if ((trip.clientRepSignatureUrl ?? '').isNotEmpty) count++;
    if ((trip.proofOfFuellingUrl ?? '').isNotEmpty) count++;
    if ((trip.inspectorSignatureUrl ?? '').isNotEmpty) count++;
    if ((trip.securitySignatureUrl ?? '').isNotEmpty) count++;
    if ((trip.driverSignatureUrl ?? '').isNotEmpty) count++;
    if ((preTrip?['odometer_photo_url']?.toString() ?? '').isNotEmpty) count++;
    if ((preTrip?['load_photo_url']?.toString() ?? '').isNotEmpty) count++;
    return count;
  }

  static kit_enums.TripStatus _mapTripStatus(String status) {
    switch (status) {
      case 'en_route':
        return kit_enums.TripStatus.enRoute;
      case 'arrived':
        return kit_enums.TripStatus.arrived;
      case 'offloaded':
        return kit_enums.TripStatus.offloaded;
      case 'completed':
        return kit_enums.TripStatus.completed;
      default:
        return kit_enums.TripStatus.assigned;
    }
  }

  static int _progressStepForStatus(String status) {
    switch (status) {
      case 'loaded':
        return 1;
      case 'en_route':
        return 2;
      case 'arrived':
        return 3;
      case 'offloaded':
      case 'completed':
        return 4;
      default:
        return 0;
    }
  }

  static String _primaryCtaLabel(String status, bool canCompleteTrip) {
    switch (status) {
      case 'en_route':
        return 'Mark as Arrived';
      case 'arrived':
        return 'Complete Delivery';
      case 'offloaded':
        return canCompleteTrip ? 'End Trip' : 'Capture End Odometer';
      case 'completed':
        return 'View Live Tracking';
      default:
        return 'Start Trip';
    }
  }

  static IconData _primaryCtaIcon(String status) {
    switch (status) {
      case 'en_route':
        return Icons.place_outlined;
      case 'arrived':
        return Icons.inventory_2_outlined;
      case 'offloaded':
        return Icons.flag_outlined;
      case 'completed':
        return Icons.map_outlined;
      default:
        return Icons.play_arrow_rounded;
    }
  }

  static PrimaryButtonVariant _primaryCtaVariant(String status) {
    switch (status) {
      case 'en_route':
      case 'arrived':
      case 'offloaded':
        return PrimaryButtonVariant.green;
      default:
        return PrimaryButtonVariant.blue;
    }
  }

  static String _durationFromNow(DateTime eta) {
    final diff = eta.difference(DateTime.now());
    if (diff.inMinutes == 0) return 'now';
    if (diff.isNegative) return '${diff.inMinutes.abs()}m ago';
    final hours = diff.inHours;
    final minutes = diff.inMinutes.remainder(60);
    if (hours <= 0) return '${diff.inMinutes}m';
    return '${hours}h ${minutes}m';
  }

  static String _deliveryContact(Trip trip) {
    final name = trip.customerContactName;
    final phone = trip.customerContactPhone;
    if ((name ?? '').isEmpty && (phone ?? '').isEmpty) return '—';
    if ((name ?? '').isNotEmpty && (phone ?? '').isNotEmpty) {
      return '$name · $phone';
    }
    return (name ?? phone)!;
  }
}

class _SummaryStripDelegate extends SliverPersistentHeaderDelegate {
  const _SummaryStripDelegate({required this.child});

  static const double _stripHeight = 208;

  final Widget child;

  @override
  double get minExtent => _stripHeight;

  @override
  double get maxExtent => _stripHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _SummaryStripDelegate oldDelegate) {
    return child != oldDelegate.child;
  }
}
