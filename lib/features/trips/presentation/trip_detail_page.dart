import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hive/hive.dart';

import '../../../core/utils/logger.dart';
import '../../../ui_kit/models/enums.dart' as kit_enums;
import '../../../ui_kit/theme/app_colors.dart';
import '../../../ui_kit/theme/app_spacing.dart';
import '../../../ui_kit/widgets/badges.dart';
import '../../../ui_kit/widgets/buttons.dart';
import '../../../ui_kit/widgets/cards.dart';
import '../../../ui_kit/widgets/navigation.dart' as kit_nav;
import '../../evidence/presentation/capture_evidence_page.dart';
import '../../chat/data/chat_repository.dart';
import '../../chat/presentation/trip_chat_page.dart';
import '../../offline/hive_boxes.dart';
import '../../tracking/service/tracking_service.dart';
import '../../maintenance/data/maintenance_repository.dart';
import '../data/trips_repository.dart';
import '../domain/trip.dart';
import '../domain/trip_stop.dart';
import 'delivery_completion_page.dart';
import 'fuel_post_trip_page.dart';
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

final tripChatUnreadProvider = FutureProvider.family<int, int>((ref, tripId) {
  return ref.read(chatRepositoryProvider).fetchTripUnreadCount(tripId);
});

class TripDetailPage extends ConsumerWidget {
  const TripDetailPage({super.key, required this.tripId});

  final int tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripAsync = ref.watch(tripDetailProvider(tripId));
    final stopsAsync = ref.watch(tripStopsProvider(tripId));
    final preTripAsync = ref.watch(preTripProvider(tripId));
    final unreadChatAsync = ref.watch(tripChatUnreadProvider(tripId));
    final trackingState = ref.watch(trackingServiceProvider);

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
          final unreadChatCount = unreadChatAsync.maybeWhen(
            data: (value) => value,
            orElse: () => 0,
          );
          final sampleAge = trackingState.lastSampleAt == null
              ? null
              : DateTime.now().difference(trackingState.lastSampleAt!);
          final liveSpeed =
              (trackingState.currentSpeedKph != null &&
                  sampleAge != null &&
                  sampleAge.inSeconds <= 15)
              ? trackingState.currentSpeedKph
              : trip.latestLocationSpeedKph;

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

          Future<void> openDispatchChat() async {
            await Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => TripChatPage(
                  tripId: trip.id,
                  tripReference: trip.referenceCode,
                  tripStatus: trip.status,
                ),
              ),
            );
            ref.invalidate(tripChatUnreadProvider(trip.id));
          }

          Future<void> markArrivedFromTrackingCard() async {
            try {
              final repo = ref.read(tripsRepositoryProvider);
              final now = DateTime.now().toIso8601String();
              await repo.updateStatus(trip.id, 'arrived');
              await repo.updateTrip(trip.id, {'arrival_time_at_site': now});
              await refreshTripData();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Arrived status updated.')),
              );
            } catch (e, st) {
              Logger.e('Mark arrived failed', e, st);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed to mark arrived: $e')),
              );
            }
          }

          Future<void> runPrimaryAction() async {
            Future<void> showMaintenanceDueBannerIfNeeded() async {
              try {
                final status = await ref
                    .read(maintenanceRepositoryProvider)
                    .fetchVehicleStatusOnly();
                if (!context.mounted) return;
                if (!status.isDueSoon && !status.isOverdue) return;
                final messenger = ScaffoldMessenger.of(context);
                messenger.clearMaterialBanners();
                messenger.showMaterialBanner(
                  MaterialBanner(
                    backgroundColor: status.isOverdue
                        ? AppColors.errorRedLight
                        : AppColors.accentOrangeLight,
                    content: Text(
                      status.isOverdue
                          ? 'Maintenance overdue for your vehicle. Inform dispatch.'
                          : 'Maintenance is due soon for your vehicle.',
                      style: TextStyle(
                        color: status.isOverdue
                            ? AppColors.errorRed
                            : AppColors.accentOrangeDark,
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: messenger.hideCurrentMaterialBanner,
                        child: const Text('Dismiss'),
                      ),
                    ],
                  ),
                );
                Future.delayed(const Duration(seconds: 8), () {
                  if (context.mounted) {
                    messenger.hideCurrentMaterialBanner();
                  }
                });
              } catch (_) {
                // Non-blocking hook: maintenance check failure should not block trip completion UX.
              }
            }

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
                  await markArrivedFromTrackingCard();
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
                  await showMaintenanceDueBannerIfNeeded();
                  return;
                case 'completed':
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Trip already completed.')),
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
                                    await openDispatchChat();
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
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'history',
                                  child: Text('View trip history'),
                                ),
                                const PopupMenuItem(
                                  value: 'issue',
                                  child: Text('Report issue'),
                                ),
                                PopupMenuItem(
                                  value: 'dispatch',
                                  child: Text(
                                    unreadChatCount > 0
                                        ? 'Contact dispatch ($unreadChatCount)'
                                        : 'Contact dispatch',
                                  ),
                                ),
                                const PopupMenuItem(
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
                              destination: _destinationLabel(trip),
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
                                  label: unreadChatCount > 0
                                      ? 'Dispatch ($unreadChatCount)'
                                      : 'Dispatch',
                                  onTap: openDispatchChat,
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
                                  title: 'Dispatcher',
                                  children: [
                                    AppSecondaryButton(
                                      label: unreadChatCount > 0
                                          ? 'Chat with Dispatcher ($unreadChatCount)'
                                          : 'Chat with Dispatcher',
                                      leadingIcon: Icons.chat_bubble_outline,
                                      onPressed: openDispatchChat,
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
                                          value: liveSpeed == null
                                              ? 'Speed unavailable'
                                              : '${liveSpeed.toStringAsFixed(0)} km/h',
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
                                _LiveTrackingStatusCard(
                                  trip: trip,
                                  onMarkArrived: markArrivedFromTrackingCard,
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
                                      value: _destinationLabel(trip),
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

  static String _destinationLabel(Trip trip) {
    String? clean(String? value) {
      final v = value?.trim();
      if (v == null || v.isEmpty) return null;
      return v;
    }

    final client = clean(trip.clientName);
    final location =
        clean(trip.destination) ??
        clean(trip.deliveryAddress) ??
        clean(trip.dropoffLocation);
    if (client != null && location != null) {
      final same = client.toLowerCase() == location.toLowerCase();
      return same ? location : '$client - $location';
    }
    return location ?? client ?? 'Destination pending';
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
        return 'Trip Completed';
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

class _LiveTrackingStatusCard extends ConsumerWidget {
  const _LiveTrackingStatusCard({
    required this.trip,
    required this.onMarkArrived,
  });

  final Trip trip;
  final Future<void> Function() onMarkArrived;

  LatLng? _destinationLatLng() {
    if (trip.destinationLat != null && trip.destinationLng != null) {
      return LatLng(trip.destinationLat!, trip.destinationLng!);
    }
    return null;
  }

  LatLng? _fallbackTruckLatLng() {
    if (trip.latestLocationLat != null && trip.latestLocationLng != null) {
      return LatLng(trip.latestLocationLat!, trip.latestLocationLng!);
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final destination = _destinationLatLng();
    final trackingState = ref.watch(trackingServiceProvider);

    return SectionCard(
      title: 'Live Tracking Status',
      children: [
        StreamBuilder<Position>(
          stream: Geolocator.getPositionStream(),
          builder: (context, snapshot) {
            final truck =
                (trackingState.currentLat != null &&
                    trackingState.currentLng != null)
                ? LatLng(trackingState.currentLat!, trackingState.currentLng!)
                : (snapshot.hasData
                      ? LatLng(
                          snapshot.data!.latitude,
                          snapshot.data!.longitude,
                        )
                      : _fallbackTruckLatLng());
            final speedKph =
                (trackingState.currentSpeedKph != null &&
                    trackingState.currentSpeedKph!.isFinite)
                ? trackingState.currentSpeedKph!.clamp(0, 999).toDouble()
                : (snapshot.hasData
                      ? (snapshot.data!.speed * 3.6).clamp(0, 999).toDouble()
                      : (trip.latestLocationSpeedKph ?? 0));
            final distanceKm = (truck != null && destination != null)
                ? Geolocator.distanceBetween(
                        truck.latitude,
                        truck.longitude,
                        destination.latitude,
                        destination.longitude,
                      ) /
                      1000
                : trip.distanceKm;
            final etaLabel = _etaFromDistance(distanceKm, speedKph);
            final elapsed = _elapsedLabel(trip.estimatedDepartureTime);

            final markers = <Marker>{
              if (truck != null)
                Marker(
                  markerId: const MarkerId('truck'),
                  position: truck,
                  infoWindow: const InfoWindow(title: 'Truck Position'),
                ),
              if (destination != null)
                Marker(
                  markerId: const MarkerId('destination'),
                  position: destination,
                  infoWindow: InfoWindow(
                    title: trip.destination ?? 'Destination',
                  ),
                ),
            };
            final traveledPoints = trackingState.path
                .map((point) => LatLng(point.lat, point.lng))
                .toList(growable: false);
            final polylines = <Polyline>{
              if (traveledPoints.length >= 2)
                Polyline(
                  polylineId: const PolylineId('traveled_path'),
                  color: AppColors.primaryBlueDark,
                  width: 5,
                  points: traveledPoints,
                ),
              if (truck != null && destination != null)
                Polyline(
                  polylineId: const PolylineId('route_hint'),
                  color: AppColors.accentOrangeDark.withValues(alpha: 0.8),
                  width: 3,
                  points: [truck, destination],
                  patterns: [PatternItem.dot, PatternItem.gap(8)],
                ),
            };

            final pendingMedia = Hive.box<Map>(
              HiveBoxes.evidenceQueue,
            ).values.where((e) => e['trip_id'] == trip.id).length;
            final pendingStatus = Hive.box<Map>(
              HiveBoxes.statusQueue,
            ).values.where((e) => e['trip_id'] == trip.id).length;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 170,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.neutral300),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: truck == null
                      ? const Center(child: Text('Location unavailable'))
                      : GoogleMap(
                          initialCameraPosition: CameraPosition(
                            target: truck,
                            zoom: 13,
                          ),
                          myLocationEnabled: true,
                          myLocationButtonEnabled: false,
                          trafficEnabled: true,
                          zoomControlsEnabled: false,
                          markers: markers,
                          polylines: polylines,
                          onTap: (_) {
                            showDialog<void>(
                              context: context,
                              builder: (_) => _ExpandedTrackingMapDialog(
                                initial: truck,
                                markers: markers,
                                polylines: polylines,
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Tap map to expand full-screen.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
                const SizedBox(height: AppSpacing.sm),
                StatGrid(
                  stats: [
                    StatBox(
                      label: 'Speed',
                      value: '${speedKph.toStringAsFixed(1)} km/h',
                      valueColor: AppColors.primaryBlue,
                    ),
                    StatBox(label: 'ETA', value: etaLabel),
                    StatBox(
                      label: 'Distance remaining',
                      value: distanceKm == null
                          ? '—'
                          : '${distanceKm.toStringAsFixed(1)} km',
                    ),
                    StatBox(label: 'Elapsed', value: elapsed),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                InfoRow(
                  label: 'Last location ping',
                  value: snapshot.hasData ? 'Just now' : 'No live ping',
                ),
                InfoRow(
                  label: 'Trip status sync',
                  value: pendingStatus == 0
                      ? 'Synced'
                      : '$pendingStatus pending',
                ),
                InfoRow(
                  label: 'Pending media count',
                  value: '$pendingMedia',
                  showDivider: false,
                ),
                if (pendingMedia > 0) ...[
                  const SizedBox(height: AppSpacing.sm),
                  AlertBanner(
                    type: kit_enums.AlertType.warning,
                    message:
                        '$pendingMedia photos uploading when signal improves',
                  ),
                ],
                if (trip.status == 'en_route') ...[
                  const SizedBox(height: AppSpacing.sm),
                  AppPrimaryButton(
                    label: "📍 I've Arrived — Mark Arrived",
                    variant: PrimaryButtonVariant.green,
                    onPressed: onMarkArrived,
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  static String _etaFromDistance(double? distanceKm, double speedKph) {
    if (distanceKm == null || speedKph <= 1) return '—';
    final minutes = ((distanceKm / speedKph) * 60).round();
    final eta = DateTime.now().add(Duration(minutes: minutes));
    final hh = eta.hour.toString().padLeft(2, '0');
    final mm = eta.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  static String _elapsedLabel(DateTime? start) {
    if (start == null) return '—';
    final d = DateTime.now().difference(start);
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return '${h}h ${m}m';
  }
}

class _ExpandedTrackingMapDialog extends StatelessWidget {
  const _ExpandedTrackingMapDialog({
    required this.initial,
    required this.markers,
    required this.polylines,
  });

  final LatLng initial;
  final Set<Marker> markers;
  final Set<Polyline> polylines;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live Map')),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(target: initial, zoom: 14),
        myLocationEnabled: true,
        trafficEnabled: true,
        markers: markers,
        polylines: polylines,
      ),
    );
  }
}
