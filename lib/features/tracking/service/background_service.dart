import 'dart:async';

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

  service.on('startTracking').listen((event) {
    token = event?['token'] as String?;
    tripId = event?['trip_id'] as int?;

    if (token != null && token!.isNotEmpty) {
      final normalized = token!.startsWith('Bearer ') ? token! : 'Bearer $token';
      dio.options.headers['Authorization'] = normalized;
      Logger.d('Background service auth set (len=${token!.length}).');
    } else {
      Logger.d('Background service missing auth token.');
    }

    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (tripId == null) return;
      final recordedAt = DateTime.now();
      Map<String, dynamic>? queuePayload;
      try {
        final position = await Geolocator.getCurrentPosition();
        final locationPayload = {
          'lat': position.latitude,
          'lng': position.longitude,
          'speed': position.speed,
          'heading': position.heading,
          'recorded_at': recordedAt.toIso8601String(),
        };
        queuePayload = {
          'trip_id': tripId,
          ...locationPayload,
        };
        await dio.post('/trips/$tripId/locations', data: {
          'location': locationPayload,
        });
        service.invoke('pingSuccess', {'recorded_at': recordedAt.toIso8601String()});
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
        if (queuePayload != null) {
          service.invoke('queuePing', queuePayload);
        }
        service.invoke('pingFailed');
      }
    });
  });

  service.on('stopTracking').listen((event) {
    timer?.cancel();
    timer = null;
    tripId = null;
    token = null;
  });
}
