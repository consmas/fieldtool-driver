import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../offline/hive_boxes.dart';
import '../fuel/data/fuel_repository.dart';
import '../tracking/data/tracking_repository.dart';
import '../trips/data/trips_repository.dart';

class SyncManager {
  SyncManager(
    this._statusBox,
    this._mediaBox,
    this._preTripBox,
    this._trackingBox,
    this._fuelLogsBox,
    this._trackingRepository,
    this._tripsRepository,
    this._fuelRepository,
  );

  final Box<Map> _statusBox;
  final Box<Map> _mediaBox;
  final Box<Map> _preTripBox;
  final Box<Map> _trackingBox;
  final Box<Map> _fuelLogsBox;
  final TrackingRepository _trackingRepository;
  final TripsRepository _tripsRepository;
  final FuelRepository _fuelRepository;
  StreamSubscription? _sub;
  bool _flushing = false;

  void start() {
    _sub ??= Connectivity().onConnectivityChanged.listen((result) {
      final hasNetwork = result.any((r) => r != ConnectivityResult.none);
      if (hasNetwork) {
        _flush();
      }
    });
  }

  Future<void> _flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      await _flushStatusQueue();
      await _flushPreTripQueue();
      await _flushMediaQueue();
      await _flushLocationQueue();
      await _flushFuelLogsQueue();
    } finally {
      _flushing = false;
    }
  }

  Future<void> _flushStatusQueue() async {
    final keys = _statusBox.keys.toList();
    for (final key in keys) {
      final item = _statusBox.get(key);
      if (item == null) continue;
      try {
        await _tripsRepository.replayStatus(
          tripId: item['trip_id'] as int,
          status: item['status'] as String,
        );
        await _statusBox.delete(key);
      } catch (_) {
        break;
      }
    }
  }

  Future<void> _flushMediaQueue() async {
    final keys = _mediaBox.keys.toList();
    for (final key in keys) {
      final item = _mediaBox.get(key);
      if (item == null) continue;
      try {
        await _tripsRepository.replayQueuedMedia(
          Map<String, dynamic>.from(item),
        );
        await _mediaBox.delete(key);
      } catch (_) {
        break;
      }
    }
  }

  Future<void> _flushPreTripQueue() async {
    final keys = _preTripBox.keys.toList();
    for (final key in keys) {
      final item = _preTripBox.get(key);
      if (item == null) continue;
      try {
        await _tripsRepository.replayQueuedPreTrip(
          Map<String, dynamic>.from(item),
        );
        await _preTripBox.delete(key);
      } catch (_) {
        break;
      }
    }
  }

  Future<void> _flushLocationQueue() async {
    final keys = _trackingBox.keys.toList()
      ..sort((a, b) {
        final left = _trackingBox.get(a);
        final right = _trackingBox.get(b);
        DateTime parse(Map? item) {
          final raw = item?['recorded_at']?.toString();
          return DateTime.tryParse(raw ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
        }

        return parse(left).compareTo(parse(right));
      });
    for (final key in keys) {
      final item = _trackingBox.get(key);
      if (item == null) continue;
      try {
        double toDouble(dynamic value, {double fallback = 0}) {
          if (value is num) return value.toDouble();
          if (value is String) return double.tryParse(value) ?? fallback;
          return fallback;
        }

        await _trackingRepository.postLocationPing(
          tripId: item['trip_id'] as int,
          lat: toDouble(item['lat']),
          lng: toDouble(item['lng']),
          speed: toDouble(item['speed']),
          heading: toDouble(item['heading']),
          recordedAt: DateTime.parse(item['recorded_at'] as String),
        );
        await _trackingBox.delete(key);
      } catch (_) {
        break;
      }
    }
  }

  Future<void> _flushFuelLogsQueue() async {
    final keys = _fuelLogsBox.keys.toList()
      ..sort((a, b) {
        final left = _fuelLogsBox.get(a);
        final right = _fuelLogsBox.get(b);
        DateTime parse(Map? item) {
          final raw = item?['recorded_at']?.toString();
          return DateTime.tryParse(raw ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
        }

        return parse(left).compareTo(parse(right));
      });
    for (final key in keys) {
      final item = _fuelLogsBox.get(key);
      if (item == null) continue;
      try {
        await _fuelRepository.replayQueuedFuelLog(
          Map<String, dynamic>.from(item),
        );
        await _fuelLogsBox.delete(key);
      } catch (_) {
        break;
      }
    }
  }

  void dispose() {
    _sub?.cancel();
  }
}

final syncManagerProvider = Provider<SyncManager>((ref) {
  final statusBox = Hive.box<Map>(HiveBoxes.statusQueue);
  final mediaBox = Hive.box<Map>(HiveBoxes.evidenceQueue);
  final preTripBox = Hive.box<Map>(HiveBoxes.preTripQueue);
  final trackingBox = Hive.box<Map>(HiveBoxes.trackingPings);
  final fuelLogsBox = Hive.box<Map>(HiveBoxes.fuelLogsQueue);
  final trackingRepo = ref.read(trackingRepositoryProvider);
  final tripsRepo = ref.read(tripsRepositoryProvider);
  final fuelRepo = ref.read(fuelRepositoryProvider);
  final manager = SyncManager(
    statusBox,
    mediaBox,
    preTripBox,
    trackingBox,
    fuelLogsBox,
    trackingRepo,
    tripsRepo,
    fuelRepo,
  );
  manager.start();
  ref.onDispose(manager.dispose);
  return manager;
});
