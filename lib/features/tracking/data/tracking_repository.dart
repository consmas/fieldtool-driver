import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';

class TrackingRepository {
  TrackingRepository(this._dio);

  final Dio _dio;

  Future<void> postLocationPing({
    required int tripId,
    required double lat,
    required double lng,
    required double speed,
    required double heading,
    required DateTime recordedAt,
  }) async {
    final speedKph = speed.isFinite ? speed.clamp(0, 999).toDouble() : 0.0;
    final headingDeg = heading.isFinite ? heading.clamp(0, 360).toDouble() : 0.0;
    await _dio.post(Endpoints.tripLocations(tripId), data: {
      'location': {
        'lat': lat,
        'lng': lng,
        'speed': speedKph,
        'heading': headingDeg,
        'recorded_at': recordedAt.toIso8601String(),
      },
    });
  }
}

final trackingRepositoryProvider = Provider<TrackingRepository>((ref) {
  final dio = ref.read(dioProvider);
  return TrackingRepository(dio);
});
