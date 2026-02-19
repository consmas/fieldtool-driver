import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';

import '../../../config/env.dart';
import '../../../core/utils/logger.dart';

class BackgroundServiceInitializer {
  static Future<void> initialize() async {
    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: backgroundServiceEntryPoint,
        autoStart: false,
        isForegroundMode: true,
        initialNotificationTitle: 'ConsMas Tracking',
        initialNotificationContent: 'Tracking is active',
        foregroundServiceNotificationId: 2001,
      ),
      iosConfiguration: IosConfiguration(
        onForeground: backgroundServiceEntryPoint,
      ),
    );
  }
}

@pragma('vm:entry-point')
void backgroundServiceEntryPoint(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();

  final dio = Dio(BaseOptions(
    baseUrl: Env.apiBaseUrl,
    headers: {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    },
  ));
  String? token;
  int? tripId;
  Timer? timer;
  Position? lastAccepted;
  Position? pendingSpike;
  double distanceMeters = 0;
  double maxSpeedKph = 0;
  double avgSpeedAccumulator = 0;
  int avgSpeedCount = 0;
  final speedWindow = <double>[];
  DateTime? lastSyncAt;
  bool offlineQueueing = false;

  Future<void> processPosition(Position position) async {
    if (tripId == null) return;
    final now = DateTime.now().toUtc();
    final recordedAt = position.timestamp.toUtc();
    final lastTs = lastAccepted?.timestamp.toUtc();

    if (lastTs != null && recordedAt.isBefore(lastTs)) {
      return;
    }
    if (lastTs != null && now.difference(recordedAt).inSeconds > 30) {
      // stale sample while newer points already exist
      return;
    }

    final weakGps = position.accuracy > 50;
    if (weakGps && lastTs != null && now.difference(lastTs).inSeconds < 60) {
      return;
    }

    double movementMeters = 0;
    double fallbackKph = 0;
    if (lastAccepted != null) {
      final prev = lastAccepted!;
      movementMeters = Geolocator.distanceBetween(
        prev.latitude,
        prev.longitude,
        position.latitude,
        position.longitude,
      );
      final prevTs = prev.timestamp.toUtc();
      final dt = recordedAt.difference(prevTs).inMilliseconds / 1000.0;
      if (dt > 0) {
        fallbackKph = (movementMeters / dt) * 3.6;
      }

      // cadence gate: 5-10s or 20-30m in active mode
      if (dt < 5 && movementMeters < 10) return;
      if (dt < 10 && movementMeters < 20) return;
    }

    final sensorKph = position.speed.isFinite && position.speed >= 0
        ? position.speed * 3.6
        : double.nan;
    var rawKph = sensorKph.isFinite ? sensorKph : fallbackKph;
    if (!rawKph.isFinite || rawKph < 0) rawKph = 0;

    // impossible jump filtering (>160 km/h) unless confirmed by next sample.
    if (rawKph > 160) {
      if (pendingSpike == null) {
        pendingSpike = position;
        return;
      }
      final prevSpikeTs = pendingSpike!.timestamp.toUtc();
      final spikeDt = recordedAt.difference(prevSpikeTs).inMilliseconds / 1000.0;
      final spikeDist = Geolocator.distanceBetween(
        pendingSpike!.latitude,
        pendingSpike!.longitude,
        position.latitude,
        position.longitude,
      );
      final spikeKph = spikeDt > 0 ? (spikeDist / spikeDt) * 3.6 : rawKph;
      if (spikeKph < 160) {
        pendingSpike = null;
        return;
      }
    } else {
      pendingSpike = null;
    }

    if (rawKph > 180) {
      return;
    }
    rawKph = rawKph.clamp(0, 180).toDouble();

    if (lastAccepted != null) {
      distanceMeters += movementMeters;
    }
    speedWindow.add(rawKph);
    if (speedWindow.length > 5) speedWindow.removeAt(0);
    final smoothedKph =
        speedWindow.fold<double>(0, (sum, v) => sum + v) / speedWindow.length;
    avgSpeedAccumulator += rawKph;
    avgSpeedCount += 1;
    maxSpeedKph = math.max(maxSpeedKph, rawKph);
    lastAccepted = position;

    final locationPayload = {
      'lat': position.latitude,
      'lng': position.longitude,
      'speed': rawKph,
      'heading': position.heading.isFinite
          ? position.heading.clamp(0, 360).toDouble()
          : 0.0,
      'recorded_at': recordedAt.toIso8601String(),
    };
    final queuePayload = {
      'trip_id': tripId,
      ...locationPayload,
    };

    try {
      await dio.post('/trips/$tripId/locations', data: {
        'location': locationPayload,
      });
      lastSyncAt = DateTime.now().toUtc();
      offlineQueueing = false;
      service.invoke('pingSuccess', {
        'recorded_at': recordedAt.toIso8601String(),
        'last_sync_at': lastSyncAt!.toIso8601String(),
        'queued_count': 0,
      });
    } catch (e, st) {
      if (e is DioException) {
        Logger.e(
          'Background ping failed (${e.response?.statusCode})',
          e.response?.data ?? e,
          st,
        );
      } else {
        Logger.e('Background ping failed', e, st);
      }
      offlineQueueing = true;
      service.invoke('queuePing', queuePayload);
      service.invoke('pingFailed');
    } finally {
      service.invoke('trackingUpdate', {
        'lat': position.latitude,
        'lng': position.longitude,
        'recorded_at': recordedAt.toIso8601String(),
        'speed_kph_raw': rawKph,
        'speed_kph_smoothed': smoothedKph,
        'avg_speed_kph': avgSpeedCount == 0 ? 0 : (avgSpeedAccumulator / avgSpeedCount),
        'max_speed_kph': maxSpeedKph,
        'distance_km': distanceMeters / 1000.0,
        'weak_gps': weakGps,
        'offline_queueing': offlineQueueing,
        'last_sync_at': lastSyncAt?.toIso8601String(),
      });
    }
  }

  service.on('startTracking').listen((event) {
    token = event?['token'] as String?;
    tripId = event?['trip_id'] as int?;
    lastAccepted = null;
    pendingSpike = null;
    distanceMeters = 0;
    maxSpeedKph = 0;
    avgSpeedAccumulator = 0;
    avgSpeedCount = 0;
    speedWindow.clear();
    lastSyncAt = null;
    offlineQueueing = false;

    if (token != null && token!.isNotEmpty) {
      final normalized = token!.startsWith('Bearer ') ? token! : 'Bearer $token';
      dio.options.headers['Authorization'] = normalized;
      Logger.d('Background service auth set (len=${token!.length}).');
    } else {
      Logger.d('Background service missing auth token.');
    }

    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 8), (_) async {
      if (tripId == null) return;
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.bestForNavigation,
        );
        await processPosition(position);
      } catch (_) {
        service.invoke('trackingUpdate', {
          'weak_gps': true,
          'offline_queueing': offlineQueueing,
          'last_sync_at': lastSyncAt?.toIso8601String(),
        });
      }
    });
  });

  service.on('stopTracking').listen((event) {
    timer?.cancel();
    timer = null;
    tripId = null;
    token = null;
    lastAccepted = null;
    pendingSpike = null;
  });
}
