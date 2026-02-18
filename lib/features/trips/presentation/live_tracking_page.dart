import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hive/hive.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/logger.dart';
import '../../../ui_kit/models/enums.dart';
import '../../../ui_kit/theme/app_colors.dart';
import '../../../ui_kit/theme/app_spacing.dart';
import '../../../ui_kit/widgets/badges.dart';
import '../../../ui_kit/widgets/cards.dart';
import '../../../ui_kit/widgets/navigation.dart';
import '../../offline/hive_boxes.dart';
import '../../tracking/service/tracking_service.dart';
import '../data/trips_repository.dart';
import '../domain/trip.dart';

class LiveTrackingPage extends ConsumerStatefulWidget {
  const LiveTrackingPage({super.key, required this.tripId});

  final int tripId;

  @override
  ConsumerState<LiveTrackingPage> createState() => _LiveTrackingPageState();
}

class _LiveTrackingPageState extends ConsumerState<LiveTrackingPage> {
  bool _loading = true;
  String? _error;
  Trip? _trip;
  Position? _position;
  StreamSubscription<Position>? _positionSub;
  GoogleMapController? _mapCtrl;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _mapCtrl?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final trip = await ref
          .read(tripsRepositoryProvider)
          .fetchTrip(widget.tripId);
      Position? current;
      try {
        final permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          await Geolocator.requestPermission();
        }
        current = await Geolocator.getCurrentPosition();
        _positionSub?.cancel();
        _positionSub = Geolocator.getPositionStream().listen((pos) {
          if (!mounted) return;
          setState(() => _position = pos);
        });
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _trip = trip;
        _position = current;
        _loading = false;
      });
    } catch (e, st) {
      Logger.e('Live tracking load failed', e, st);
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  LatLng? get _truckLatLng {
    if (_position != null) {
      return LatLng(_position!.latitude, _position!.longitude);
    }
    if (_trip?.latestLocationLat != null && _trip?.latestLocationLng != null) {
      return LatLng(_trip!.latestLocationLat!, _trip!.latestLocationLng!);
    }
    return null;
  }

  LatLng? get _destinationLatLng {
    if (_trip?.destinationLat != null && _trip?.destinationLng != null) {
      return LatLng(_trip!.destinationLat!, _trip!.destinationLng!);
    }
    return null;
  }

  double get _speedKph {
    if (_position != null) {
      final mps = _position!.speed;
      if (mps.isFinite) return (mps * 3.6).clamp(0, 999);
    }
    return _trip?.latestLocationSpeedKph ?? 0;
  }

  double? get _distanceRemainingKm {
    final from = _truckLatLng;
    final to = _destinationLatLng;
    if (from == null || to == null) return null;
    final meters = Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      to.latitude,
      to.longitude,
    );
    return meters / 1000;
  }

  String get _etaLabel {
    final distance = _distanceRemainingKm;
    final speed = _speedKph;
    if (distance == null || speed <= 1) return '—';
    final hours = distance / speed;
    final minutes = (hours * 60).round();
    final eta = DateTime.now().add(Duration(minutes: minutes));
    final hh = eta.hour.toString().padLeft(2, '0');
    final mm = eta.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  String get _elapsedLabel {
    final start = _trip?.estimatedDepartureTime;
    if (start == null) return '—';
    final d = DateTime.now().difference(start);
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return '${h}h ${m}m';
  }

  int get _pendingMediaCount {
    final box = Hive.box<Map>(HiveBoxes.evidenceQueue);
    return box.values.where((e) => e['trip_id'] == widget.tripId).length;
  }

  int get _pendingStatusCount {
    final box = Hive.box<Map>(HiveBoxes.statusQueue);
    return box.values.where((e) => e['trip_id'] == widget.tripId).length;
  }

  int get _pendingPreTripCount {
    final box = Hive.box<Map>(HiveBoxes.preTripQueue);
    return box.values.where((e) => e['trip_id'] == widget.tripId).length;
  }

  Future<void> _openNavigation() async {
    final dest = _destinationLatLng;
    Uri uri;
    if (dest != null) {
      uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${dest.latitude},${dest.longitude}&travelmode=driving',
      );
    } else {
      final q = Uri.encodeComponent(_trip?.destination ?? '');
      uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$q');
    }

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Google Maps.')),
      );
    }
  }

  Future<void> _markArrived() async {
    try {
      final repo = ref.read(tripsRepositoryProvider);
      final now = DateTime.now().toIso8601String();
      await repo.updateStatus(widget.tripId, 'arrived');
      await repo.updateTrip(widget.tripId, {'arrival_time_at_site': now});
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Arrived status updated.')));
      Navigator.pop(context, true);
    } catch (e, st) {
      Logger.e('Mark arrived failed', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to mark arrived: $e')));
    }
  }

  Set<Marker> get _markers {
    final markers = <Marker>{};
    final truck = _truckLatLng;
    final dest = _destinationLatLng;
    if (truck != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('truck'),
          position: truck,
          infoWindow: const InfoWindow(title: 'Truck Position'),
        ),
      );
    }
    if (dest != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: dest,
          infoWindow: InfoWindow(title: _trip?.destination ?? 'Destination'),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
        ),
      );
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Live Tracking Status')),
        body: Center(child: Text('Failed to load: $_error')),
      );
    }

    final trackingState = ref.watch(trackingServiceProvider);
    final truck = _truckLatLng;

    return Scaffold(
      appBar: AppBar(title: const Text('Live Tracking Status')),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFF6FAFF), Color(0xFFFFFFFF)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          StickyBottomBar(
            bottomBar: BottomActionBar(
              primary: ElevatedButton.icon(
                onPressed: _markArrived,
                icon: const Icon(Icons.place),
                label: const Text('📍 I\'ve Arrived — Mark Arrived'),
              ),
              secondary: OutlinedButton.icon(
                onPressed: _openNavigation,
                icon: const Icon(Icons.navigation),
                label: const Text('Navigate'),
              ),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: [
                  SectionCard(
                    title: 'Journey Map',
                    children: [
                      GestureDetector(
                        onTap: truck == null
                            ? null
                            : () {
                                showDialog<void>(
                                  context: context,
                                  builder: (_) => _ExpandedMapDialog(
                                    initial: truck,
                                    markers: _markers,
                                  ),
                                );
                              },
                        child: Container(
                          height: 180,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.neutral300),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: truck == null
                              ? const Center(
                                  child: Text('Location unavailable'),
                                )
                              : GoogleMap(
                                  initialCameraPosition: CameraPosition(
                                    target: truck,
                                    zoom: 13,
                                  ),
                                  myLocationEnabled: true,
                                  myLocationButtonEnabled: false,
                                  markers: _markers,
                                  zoomControlsEnabled: false,
                                  onMapCreated: (c) => _mapCtrl = c,
                                ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Tap map to expand full-screen.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _StatsGrid(
                    speedKph: _speedKph,
                    eta: _etaLabel,
                    distanceKm: _distanceRemainingKm,
                    elapsed: _elapsedLabel,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SectionCard(
                    title: 'Sync Status',
                    children: [
                      InfoRow(
                        label: 'Last location ping',
                        value:
                            trackingState.lastPing?.toLocal().toString() ?? '—',
                      ),
                      InfoRow(
                        label: 'Trip status sync queue',
                        value: _pendingStatusCount == 0
                            ? 'Synced'
                            : '$_pendingStatusCount pending',
                      ),
                      InfoRow(
                        label: 'Pending media uploads',
                        value: _pendingMediaCount.toString(),
                      ),
                      InfoRow(
                        label: 'Pending pre-trip writes',
                        value: _pendingPreTripCount.toString(),
                      ),
                    ],
                  ),
                  if (_pendingMediaCount > 0) ...[
                    const SizedBox(height: AppSpacing.md),
                    AlertBanner(
                      type: AlertType.warning,
                      message:
                          '$_pendingMediaCount photos uploading when signal improves',
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({
    required this.speedKph,
    required this.eta,
    required this.distanceKm,
    required this.elapsed,
  });

  final double speedKph;
  final String eta;
  final double? distanceKm;
  final String elapsed;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      crossAxisCount: 2,
      crossAxisSpacing: AppSpacing.sm,
      mainAxisSpacing: AppSpacing.sm,
      childAspectRatio: 2.15,
      children: [
        _StatBox(label: 'Speed', value: '${speedKph.toStringAsFixed(1)} km/h'),
        _StatBox(label: 'ETA', value: eta),
        _StatBox(
          label: 'Distance Remaining',
          value: distanceKm == null
              ? '—'
              : '${distanceKm!.toStringAsFixed(1)} km',
        ),
        _StatBox(label: 'Elapsed', value: elapsed),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.neutral200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _ExpandedMapDialog extends StatelessWidget {
  const _ExpandedMapDialog({required this.initial, required this.markers});

  final LatLng initial;
  final Set<Marker> markers;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live Map')),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(target: initial, zoom: 14),
        myLocationEnabled: true,
        markers: markers,
      ),
    );
  }
}
