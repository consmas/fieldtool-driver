import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hive/hive.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/env.dart';
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
  static const double _overspeedThresholdKph = 80;
  bool _loading = true;
  String? _error;
  Trip? _trip;
  Position? _position;
  StreamSubscription<Position>? _positionSub;
  Timer? _tripRefreshTimer;
  GoogleMapController? _mapCtrl;
  bool _autoCenter = true;
  DateTime? _lastAutoCenterAt;
  List<LatLng> _routePoints = const <LatLng>[];
  double? _routeDistanceKm;
  Duration? _routeDuration;
  DateTime? _routeEtaAt;
  DateTime? _lastRouteFetchAt;
  LatLng? _lastRouteOrigin;
  LatLng? _lastRouteDestination;
  bool _routeLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _tripRefreshTimer?.cancel();
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
      _tripRefreshTimer?.cancel();
      _tripRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        _refreshTrip();
      });

      final trackingCtrl = ref.read(trackingServiceProvider.notifier);
      final trackingState = ref.read(trackingServiceProvider);
      final terminal = trip.status == 'completed' || trip.status == 'cancelled';
      if (trip.status == 'en_route' && !trackingState.running) {
        try {
          await trackingCtrl.startTracking(tripId: widget.tripId);
        } catch (e, st) {
          Logger.e('Auto-start tracking failed', e, st);
        }
      } else if (terminal && trackingState.running) {
        await trackingCtrl.stopTracking();
      }
    } catch (e, st) {
      Logger.e('Live tracking load failed', e, st);
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _refreshTrip() async {
    try {
      final trip = await ref
          .read(tripsRepositoryProvider)
          .fetchTrip(widget.tripId);
      if (!mounted) return;
      setState(() => _trip = trip);
    } catch (_) {}
  }

  LatLng? get _truckLatLng {
    final tracking = ref.read(trackingServiceProvider);
    if (tracking.currentLat != null && tracking.currentLng != null) {
      return LatLng(tracking.currentLat!, tracking.currentLng!);
    }
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

  double? get _speedKph {
    final tracking = ref.read(trackingServiceProvider);
    final sampleAge = tracking.lastSampleAt == null
        ? null
        : DateTime.now().difference(tracking.lastSampleAt!);
    if (tracking.currentSpeedKph != null &&
        sampleAge != null &&
        sampleAge.inSeconds <= 15) {
      return tracking.currentSpeedKph!.clamp(0, 999).toDouble();
    }
    if (_position != null) {
      final mps = _position!.speed;
      if (mps.isFinite) return (mps * 3.6).clamp(0, 999).toDouble();
    }
    return _trip?.latestLocationSpeedKph;
  }

  double? get _distanceRemainingKm {
    if (_routeDistanceKm != null) return _routeDistanceKm;
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

  int get _pendingLocationCount {
    final box = Hive.box<Map>(HiveBoxes.trackingPings);
    return box.values.where((e) => e['trip_id'] == widget.tripId).length;
  }

  Set<Polyline> _buildPolylines(TrackingState trackingState, LatLng? truck) {
    final points = trackingState.path
        .map((p) => LatLng(p.lat, p.lng))
        .toList(growable: false);
    final polylines = <Polyline>{};
    if (points.length >= 2) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('traveled_path'),
          color: AppColors.primaryBlueDark,
          width: 5,
          points: points,
        ),
      );
    }
    final destination = _destinationLatLng;
    if (_routePoints.length >= 2) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('driving_route'),
          color: AppColors.primaryBlue,
          width: 4,
          points: _routePoints,
        ),
      );
    } else if (truck != null && destination != null) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('route_hint'),
          color: AppColors.accentOrangeDark.withValues(alpha: 0.8),
          width: 3,
          points: [truck, destination],
          patterns: [PatternItem.dot, PatternItem.gap(8)],
        ),
      );
    }
    return polylines;
  }

  void _maybeAutoCenter(LatLng? truck) {
    if (!_autoCenter || truck == null || _mapCtrl == null) return;
    final now = DateTime.now();
    final last = _lastAutoCenterAt;
    if (last != null && now.difference(last).inMilliseconds < 1200) return;
    _lastAutoCenterAt = now;
    _mapCtrl!.animateCamera(CameraUpdate.newLatLng(truck));
  }

  void _openFullScreenMap(LatLng initial, Set<Polyline> polylines) {
    showDialog<void>(
      context: context,
      builder: (_) => _ExpandedMapDialog(
        initial: initial,
        markers: _markers,
        polylines: polylines,
      ),
    );
  }

  bool _shouldRefreshRoute(LatLng origin, LatLng destination) {
    final lastFetch = _lastRouteFetchAt;
    if (lastFetch == null) return true;
    if (DateTime.now().difference(lastFetch).inSeconds >= 20) return true;
    if (_lastRouteOrigin == null || _lastRouteDestination == null) return true;
    final originShift = Geolocator.distanceBetween(
      _lastRouteOrigin!.latitude,
      _lastRouteOrigin!.longitude,
      origin.latitude,
      origin.longitude,
    );
    final destinationShift = Geolocator.distanceBetween(
      _lastRouteDestination!.latitude,
      _lastRouteDestination!.longitude,
      destination.latitude,
      destination.longitude,
    );
    return originShift >= 50 || destinationShift >= 20;
  }

  Future<void> _maybeFetchDirectionsRoute(
    LatLng? origin,
    LatLng? destination,
  ) async {
    if (origin == null || destination == null || _routeLoading) return;
    if (!_shouldRefreshRoute(origin, destination)) return;
    if (Env.googleMapsApiKey.trim().isEmpty) return;

    _routeLoading = true;
    try {
      final routesResp = await Dio().post<Map<String, dynamic>>(
        'https://routes.googleapis.com/directions/v2:computeRoutes',
        options: Options(
          headers: {
            'X-Goog-Api-Key': Env.googleMapsApiKey,
            'X-Goog-FieldMask':
                'routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline',
          },
        ),
        data: {
          'origin': {
            'location': {
              'latLng': {
                'latitude': origin.latitude,
                'longitude': origin.longitude,
              },
            },
          },
          'destination': {
            'location': {
              'latLng': {
                'latitude': destination.latitude,
                'longitude': destination.longitude,
              },
            },
          },
          'travelMode': 'DRIVE',
          'routingPreference': 'TRAFFIC_AWARE_OPTIMAL',
          'polylineQuality': 'OVERVIEW',
          'polylineEncoding': 'ENCODED_POLYLINE',
        },
      );

      final routesData = routesResp.data ?? const <String, dynamic>{};
      final routes = (routesData['routes'] as List?) ?? const <dynamic>[];
      if (routes.isNotEmpty) {
        final route = routes.first as Map<String, dynamic>;
        final encoded =
            ((route['polyline'] as Map?)?['encodedPolyline'])?.toString() ?? '';
        final decoded = _decodePolyline(encoded);
        final distanceMeters =
            ((route['distanceMeters'] as num?)?.toDouble() ?? 0);
        final duration = _parseGoogleDuration(route['duration']?.toString());
        if (decoded.length >= 2 && mounted) {
          setState(() {
            _routePoints = decoded;
            _routeDistanceKm = distanceMeters > 0
                ? distanceMeters / 1000
                : null;
            _routeDuration = duration;
            _routeEtaAt = duration == null
                ? null
                : DateTime.now().add(duration);
            _lastRouteFetchAt = DateTime.now();
            _lastRouteOrigin = origin;
            _lastRouteDestination = destination;
          });
        }
        return;
      }

      final directionsResp = await Dio().get<Map<String, dynamic>>(
        'https://maps.googleapis.com/maps/api/directions/json',
        queryParameters: {
          'origin': '${origin.latitude},${origin.longitude}',
          'destination': '${destination.latitude},${destination.longitude}',
          'mode': 'driving',
          'alternatives': 'false',
          'departure_time': 'now',
          'traffic_model': 'best_guess',
          'key': Env.googleMapsApiKey,
        },
      );
      final data = directionsResp.data ?? const <String, dynamic>{};
      final status = data['status']?.toString();
      final fallbackRoutes = (data['routes'] as List?) ?? const <dynamic>[];
      if (status == 'OK' && fallbackRoutes.isNotEmpty) {
        final route = fallbackRoutes.first as Map<String, dynamic>;
        final encoded =
            ((route['overview_polyline'] as Map?)?['points'])?.toString() ?? '';
        final decoded = _decodePolyline(encoded);
        final legs = (route['legs'] as List?) ?? const <dynamic>[];
        var totalDistanceMeters = 0.0;
        var totalDurationSeconds = 0.0;
        for (final leg in legs) {
          final map = leg is Map ? leg : null;
          if (map == null) continue;
          final distVal = ((map['distance'] as Map?)?['value']);
          final durTrafficVal =
              ((map['duration_in_traffic'] as Map?)?['value']);
          final durVal = ((map['duration'] as Map?)?['value']);
          if (distVal is num) totalDistanceMeters += distVal.toDouble();
          if (durTrafficVal is num) {
            totalDurationSeconds += durTrafficVal.toDouble();
          } else if (durVal is num) {
            totalDurationSeconds += durVal.toDouble();
          }
        }
        if (decoded.length >= 2 && mounted) {
          final duration = totalDurationSeconds > 0
              ? Duration(seconds: totalDurationSeconds.round())
              : null;
          setState(() {
            _routePoints = decoded;
            _routeDistanceKm = totalDistanceMeters > 0
                ? totalDistanceMeters / 1000
                : null;
            _routeDuration = duration;
            _routeEtaAt = duration == null
                ? null
                : DateTime.now().add(duration);
            _lastRouteFetchAt = DateTime.now();
            _lastRouteOrigin = origin;
            _lastRouteDestination = destination;
          });
        }
      }
    } catch (e, st) {
      Logger.e('Directions route fetch failed', e, st);
    } finally {
      _routeLoading = false;
    }
  }

  Duration? _parseGoogleDuration(String? value) {
    if (value == null || value.isEmpty || !value.endsWith('s')) return null;
    final raw = value.substring(0, value.length - 1);
    final seconds = double.tryParse(raw);
    if (seconds == null || seconds <= 0) return null;
    return Duration(milliseconds: (seconds * 1000).round());
  }

  List<LatLng> _decodePolyline(String encoded) {
    final coordinates = <LatLng>[];
    var index = 0;
    var lat = 0;
    var lng = 0;
    while (index < encoded.length) {
      var shift = 0;
      var result = 0;
      int byte;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      final dLat = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lat += dLat;

      shift = 0;
      result = 0;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      final dLng = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lng += dLng;

      coordinates.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return coordinates;
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
    final speedKph = _speedKph;
    final distanceRemainingKm = _distanceRemainingKm;
    final etaFromRoute = _routeEtaAt;
    final polylines = _buildPolylines(trackingState, truck);
    _maybeFetchDirectionsRoute(truck, _destinationLatLng);
    final speedUnavailable =
        trackingState.lastSampleAt == null ||
        DateTime.now().difference(trackingState.lastSampleAt!).inSeconds > 15;

    _maybeAutoCenter(truck);

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
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Tracking: ${trackingState.trackingStatusLabel}',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: trackingState.offlineQueueing
                                        ? AppColors.accentOrangeDark
                                        : (trackingState.weakGps
                                              ? AppColors.errorRed
                                              : AppColors.successGreen),
                                  ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () =>
                                setState(() => _autoCenter = !_autoCenter),
                            icon: Icon(
                              _autoCenter
                                  ? Icons.gps_fixed
                                  : Icons.gps_not_fixed,
                            ),
                            label: Text(
                              _autoCenter
                                  ? 'Auto-center ON'
                                  : 'Auto-center OFF',
                            ),
                          ),
                        ],
                      ),
                      Container(
                        height: 180,
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
                                markers: _markers,
                                polylines: polylines,
                                zoomControlsEnabled: false,
                                onTap: (_) =>
                                    _openFullScreenMap(truck, polylines),
                                onCameraMoveStarted: () {
                                  if (_autoCenter) {
                                    setState(() => _autoCenter = false);
                                  }
                                },
                                onMapCreated: (c) => _mapCtrl = c,
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
                    speedKph: speedUnavailable ? null : speedKph,
                    averageSpeedKph: trackingState.averageSpeedKph,
                    maxSpeedKph: trackingState.maxSpeedKph,
                    distanceCoveredKm: trackingState.distanceKm,
                    distanceRemainingKm: distanceRemainingKm,
                    etaAt: etaFromRoute,
                    etaDuration: _routeDuration,
                    routeBasedDistance: _routeDistanceKm != null,
                    destinationAvailable: _destinationLatLng != null,
                    lastUpdated: trackingState.lastSampleAt,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if ((speedKph ?? 0) >= _overspeedThresholdKph) ...[
                    AlertBanner(
                      type: AlertType.warning,
                      message:
                          'Overspeed warning: ${speedKph!.toStringAsFixed(1)} km/h (threshold ${_overspeedThresholdKph.toStringAsFixed(0)}).',
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  SectionCard(
                    title: 'Sync Status',
                    children: [
                      InfoRow(
                        label: 'Tracking state',
                        value: trackingState.trackingStatusLabel,
                      ),
                      InfoRow(
                        label: 'Last location ping',
                        value:
                            trackingState.lastPing?.toLocal().toString() ?? '—',
                      ),
                      InfoRow(
                        label: 'Last sync time',
                        value:
                            trackingState.lastSyncAt?.toLocal().toString() ??
                            '—',
                      ),
                      InfoRow(
                        label: 'Queued location pings',
                        value:
                            '${trackingState.queuedCount} (box: $_pendingLocationCount)',
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
                        showDivider: false,
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
    required this.averageSpeedKph,
    required this.maxSpeedKph,
    required this.distanceCoveredKm,
    required this.distanceRemainingKm,
    required this.etaAt,
    required this.etaDuration,
    required this.routeBasedDistance,
    required this.destinationAvailable,
    required this.lastUpdated,
  });

  final double? speedKph;
  final double averageSpeedKph;
  final double maxSpeedKph;
  final double distanceCoveredKm;
  final double? distanceRemainingKm;
  final DateTime? etaAt;
  final Duration? etaDuration;
  final bool routeBasedDistance;
  final bool destinationAvailable;
  final DateTime? lastUpdated;

  @override
  Widget build(BuildContext context) {
    final etaText = etaAt == null
        ? '—'
        : '${etaAt!.hour.toString().padLeft(2, '0')}:${etaAt!.minute.toString().padLeft(2, '0')}';
    final etaSubText = etaDuration == null
        ? null
        : '${etaDuration!.inMinutes} min';
    final lastUpdatedText = lastUpdated == null
        ? '—'
        : '${lastUpdated!.hour.toString().padLeft(2, '0')}:${lastUpdated!.minute.toString().padLeft(2, '0')}:${lastUpdated!.second.toString().padLeft(2, '0')}';
    return GridView.count(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      crossAxisCount: 2,
      crossAxisSpacing: AppSpacing.sm,
      mainAxisSpacing: AppSpacing.sm,
      childAspectRatio: 2.15,
      children: [
        _StatBox(
          label: 'Current Speed',
          value: speedKph == null
              ? 'Speed unavailable'
              : '${speedKph!.toStringAsFixed(1)} km/h',
        ),
        _StatBox(
          label: 'Average Speed',
          value: '${averageSpeedKph.toStringAsFixed(1)} km/h',
        ),
        _StatBox(
          label: 'Max Speed',
          value: '${maxSpeedKph.toStringAsFixed(1)} km/h',
        ),
        _StatBox(
          label: 'Distance Covered',
          value: '${distanceCoveredKm.toStringAsFixed(2)} km',
        ),
        _StatBox(
          label: 'Distance Remaining',
          value: !destinationAvailable
              ? 'Destination coords unavailable'
              : (distanceRemainingKm == null
                    ? '—'
                    : '${distanceRemainingKm!.toStringAsFixed(2)} km'),
          caption: routeBasedDistance ? 'Road route' : 'Straight-line',
        ),
        _StatBox(label: 'ETA (Google)', value: etaText, caption: etaSubText),
        _StatBox(label: 'Last Updated', value: lastUpdatedText),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value, this.caption});

  final String label;
  final String value;
  final String? caption;

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
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(
              caption!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExpandedMapDialog extends StatelessWidget {
  const _ExpandedMapDialog({
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
