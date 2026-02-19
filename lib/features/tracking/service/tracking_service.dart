import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/auth/token_storage.dart';
import '../../../core/utils/logger.dart';
import '../data/tracking_queue.dart';

class TrackingPoint {
  const TrackingPoint({
    required this.lat,
    required this.lng,
    required this.recordedAt,
  });

  final double lat;
  final double lng;
  final DateTime recordedAt;
}

class TrackingState {
  const TrackingState({
    required this.running,
    this.lastPing,
    this.lastSyncAt,
    this.lastSampleAt,
    this.queuedCount = 0,
    this.offlineQueueing = false,
    this.weakGps = false,
    this.currentLat,
    this.currentLng,
    this.currentSpeedKph,
    this.rawSpeedKph,
    this.averageSpeedKph = 0,
    this.maxSpeedKph = 0,
    this.distanceKm = 0,
    this.path = const <TrackingPoint>[],
  });

  final bool running;
  final DateTime? lastPing;
  final DateTime? lastSyncAt;
  final DateTime? lastSampleAt;
  final int queuedCount;
  final bool offlineQueueing;
  final bool weakGps;
  final double? currentLat;
  final double? currentLng;
  final double? currentSpeedKph;
  final double? rawSpeedKph;
  final double averageSpeedKph;
  final double maxSpeedKph;
  final double distanceKm;
  final List<TrackingPoint> path;

  String get trackingStatusLabel {
    if (!running) return 'Stopped';
    if (offlineQueueing) return 'Offline Queueing';
    if (weakGps) return 'Weak GPS';
    return 'Active';
  }

  TrackingState copyWith({
    bool? running,
    DateTime? lastPing,
    DateTime? lastSyncAt,
    DateTime? lastSampleAt,
    int? queuedCount,
    bool? offlineQueueing,
    bool? weakGps,
    double? currentLat,
    double? currentLng,
    double? currentSpeedKph,
    double? rawSpeedKph,
    double? averageSpeedKph,
    double? maxSpeedKph,
    double? distanceKm,
    List<TrackingPoint>? path,
  }) {
    return TrackingState(
      running: running ?? this.running,
      lastPing: lastPing ?? this.lastPing,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      lastSampleAt: lastSampleAt ?? this.lastSampleAt,
      queuedCount: queuedCount ?? this.queuedCount,
      offlineQueueing: offlineQueueing ?? this.offlineQueueing,
      weakGps: weakGps ?? this.weakGps,
      currentLat: currentLat ?? this.currentLat,
      currentLng: currentLng ?? this.currentLng,
      currentSpeedKph: currentSpeedKph ?? this.currentSpeedKph,
      rawSpeedKph: rawSpeedKph ?? this.rawSpeedKph,
      averageSpeedKph: averageSpeedKph ?? this.averageSpeedKph,
      maxSpeedKph: maxSpeedKph ?? this.maxSpeedKph,
      distanceKm: distanceKm ?? this.distanceKm,
      path: path ?? this.path,
    );
  }
}

class TrackingController extends StateNotifier<TrackingState> {
  TrackingController(this._storage, this._queue)
      : super(const TrackingState(running: false)) {
    _listen();
    state = state.copyWith(queuedCount: _queue.count);
  }

  final TokenStorage _storage;
  final TrackingQueue _queue;
  final FlutterBackgroundService _service = FlutterBackgroundService();
  StreamSubscription? _pingSub;
  StreamSubscription? _queueSub;
  StreamSubscription? _failedSub;
  StreamSubscription? _trackingSub;

  void _listen() {
    _pingSub = _service.on('pingSuccess').listen((event) {
      final timestamp = event?['recorded_at'] as String?;
      final queued = event?['queued_count'];
      final lastSyncAt = event?['last_sync_at'] as String?;
      state = state.copyWith(
        running: true,
        lastPing: timestamp != null ? DateTime.tryParse(timestamp) : DateTime.now(),
        lastSyncAt: lastSyncAt != null ? DateTime.tryParse(lastSyncAt) : DateTime.now(),
        offlineQueueing: false,
        queuedCount: queued is num ? queued.toInt() : _queue.count,
      );
    });
    _queueSub = _service.on('queuePing').listen((event) async {
      if (event == null) return;
      await _queue.enqueue(Map<String, dynamic>.from(event));
      Logger.d('Queued ping from background service.');
      state = state.copyWith(
        queuedCount: _queue.count,
        offlineQueueing: true,
      );
    });
    _failedSub = _service.on('pingFailed').listen((event) {
      state = state.copyWith(
        offlineQueueing: true,
        queuedCount: _queue.count,
      );
    });
    _trackingSub = _service.on('trackingUpdate').listen((event) {
      if (event == null) return;
      double? toDouble(dynamic value) {
        if (value is num) return value.toDouble();
        if (value is String) return double.tryParse(value);
        return null;
      }

      DateTime? toDate(dynamic value) {
        if (value is String) return DateTime.tryParse(value);
        return null;
      }

      final lat = toDouble(event['lat']);
      final lng = toDouble(event['lng']);
      final recordedAt = toDate(event['recorded_at']) ?? DateTime.now();
      final existing = state.path;
      final updatedPath = <TrackingPoint>[
        ...existing,
        if (lat != null && lng != null)
          TrackingPoint(
            lat: lat,
            lng: lng,
            recordedAt: recordedAt,
          ),
      ];
      const maxPoints = 500;
      final trimmedPath = updatedPath.length > maxPoints
          ? updatedPath.sublist(updatedPath.length - maxPoints)
          : updatedPath;

      state = state.copyWith(
        running: true,
        lastSampleAt: recordedAt,
        currentLat: lat,
        currentLng: lng,
        currentSpeedKph: toDouble(event['speed_kph_smoothed']),
        rawSpeedKph: toDouble(event['speed_kph_raw']),
        averageSpeedKph: (toDouble(event['avg_speed_kph']) ?? state.averageSpeedKph)
            .clamp(0, 999)
            .toDouble(),
        maxSpeedKph: math.max(
          state.maxSpeedKph,
          (toDouble(event['max_speed_kph']) ?? state.maxSpeedKph).clamp(0, 999),
        ),
        distanceKm: (toDouble(event['distance_km']) ?? state.distanceKm)
            .clamp(0, 100000)
            .toDouble(),
        weakGps: event['weak_gps'] == true,
        queuedCount: (event['queued_count'] is num)
            ? (event['queued_count'] as num).toInt()
            : _queue.count,
        lastSyncAt: toDate(event['last_sync_at']) ?? state.lastSyncAt,
        offlineQueueing: event['offline_queueing'] == true || _queue.count > 0,
        path: trimmedPath,
      );
    });
  }

  Future<void> startTracking({required int tripId}) async {
    final token = await _storage.readToken();
    if (token == null || token.isEmpty) {
      throw Exception('Missing auth token.');
    }
    Logger.d('Starting tracking for trip $tripId (token len=${token.length}).');

    final locStatus = await Permission.locationWhenInUse.request();
    final bgStatus = await Permission.locationAlways.request();
    final notifStatus = await Permission.notification.request();

    if (!locStatus.isGranted && !bgStatus.isGranted) {
      throw Exception('Location permission not granted.');
    }
    if (!notifStatus.isGranted) {
      throw Exception('Notification permission not granted.');
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled.');
    }

    await _service.startService();
    _service.invoke('startTracking', {
      'trip_id': tripId,
      'token': token,
    });
    state = state.copyWith(
      running: true,
      queuedCount: _queue.count,
    );
  }

  Future<void> stopTracking() async {
    _service.invoke('stopTracking');
    state = TrackingState(
      running: false,
      lastPing: state.lastPing,
      lastSyncAt: state.lastSyncAt,
      lastSampleAt: state.lastSampleAt,
      queuedCount: _queue.count,
      distanceKm: state.distanceKm,
      averageSpeedKph: state.averageSpeedKph,
      maxSpeedKph: state.maxSpeedKph,
      path: state.path,
    );
  }

  @override
  void dispose() {
    _pingSub?.cancel();
    _queueSub?.cancel();
    _failedSub?.cancel();
    _trackingSub?.cancel();
    super.dispose();
  }
}

final trackingServiceProvider = StateNotifierProvider<TrackingController, TrackingState>((ref) {
  final storage = ref.read(tokenStorageProvider);
  final queue = ref.read(trackingQueueProvider);
  return TrackingController(storage, queue);
});
