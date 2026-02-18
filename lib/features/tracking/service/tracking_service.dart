import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/auth/token_storage.dart';
import '../../../core/utils/logger.dart';
import '../data/tracking_queue.dart';

class TrackingState {
  const TrackingState({
    required this.running,
    this.lastPing,
  });

  final bool running;
  final DateTime? lastPing;

  TrackingState copyWith({
    bool? running,
    DateTime? lastPing,
  }) {
    return TrackingState(
      running: running ?? this.running,
      lastPing: lastPing ?? this.lastPing,
    );
  }
}

class TrackingController extends StateNotifier<TrackingState> {
  TrackingController(this._storage, this._queue)
      : super(const TrackingState(running: false)) {
    _listen();
  }

  final TokenStorage _storage;
  final TrackingQueue _queue;
  final FlutterBackgroundService _service = FlutterBackgroundService();
  StreamSubscription? _pingSub;
  StreamSubscription? _queueSub;

  void _listen() {
    _pingSub = _service.on('pingSuccess').listen((event) {
      final timestamp = event?['recorded_at'] as String?;
      state = state.copyWith(
        running: true,
        lastPing: timestamp != null ? DateTime.tryParse(timestamp) : DateTime.now(),
      );
    });
    _queueSub = _service.on('queuePing').listen((event) async {
      if (event == null) return;
      await _queue.enqueue(Map<String, dynamic>.from(event));
      Logger.d('Queued ping from background service.');
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
    state = state.copyWith(running: true);
  }

  Future<void> stopTracking() async {
    _service.invoke('stopTracking');
    state = state.copyWith(running: false);
  }

  @override
  void dispose() {
    _pingSub?.cancel();
    _queueSub?.cancel();
    super.dispose();
  }
}

final trackingServiceProvider = StateNotifierProvider<TrackingController, TrackingState>((ref) {
  final storage = ref.read(tokenStorageProvider);
  final queue = ref.read(trackingQueueProvider);
  return TrackingController(storage, queue);
});
