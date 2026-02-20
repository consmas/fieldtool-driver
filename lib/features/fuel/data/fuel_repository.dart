import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/auth/token_storage.dart';
import '../../offline/hive_boxes.dart';

enum FuelLogSyncStatus { queued, synced, failed }

class FuelLogSubmission {
  FuelLogSubmission({
    required this.localId,
    required this.scope,
    this.tripId,
    this.vehicleId,
    required this.litres,
    required this.cost,
    required this.odometerKm,
    required this.fullTank,
    this.station,
    this.note,
    required this.recordedAt,
    required this.status,
  });

  final String localId;
  final String scope; // trip | vehicle
  final int? tripId;
  final int? vehicleId;
  final double litres;
  final double cost;
  final double odometerKm;
  final bool fullTank;
  final String? station;
  final String? note;
  final DateTime recordedAt;
  final FuelLogSyncStatus status;

  factory FuelLogSubmission.fromMap(Map<String, dynamic> map) {
    double toDouble(dynamic value) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0;
      return 0;
    }

    int? toInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value);
      return null;
    }

    FuelLogSyncStatus parseStatus(dynamic value) {
      final v = (value ?? '').toString().toLowerCase();
      if (v == 'synced') return FuelLogSyncStatus.synced;
      if (v == 'failed') return FuelLogSyncStatus.failed;
      return FuelLogSyncStatus.queued;
    }

    return FuelLogSubmission(
      localId: (map['local_id'] ?? '').toString(),
      scope: (map['scope'] ?? 'trip').toString(),
      tripId: toInt(map['trip_id']),
      vehicleId: toInt(map['vehicle_id']),
      litres: toDouble(map['litres']),
      cost: toDouble(map['cost']),
      odometerKm: toDouble(map['odometer_km']),
      fullTank: map['full_tank'] == true || map['full_tank']?.toString() == '1',
      station: map['station']?.toString(),
      note: map['note']?.toString(),
      recordedAt:
          DateTime.tryParse(map['recorded_at']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
      status: parseStatus(map['sync_status']),
    );
  }
}

class DriverFuelAnalysis {
  DriverFuelAnalysis({
    required this.driverId,
    this.averageKmPerLitre,
    this.totalLitres,
    this.totalCost,
    this.totalDistanceKm,
    this.monthlyTrend = const <Map<String, dynamic>>[],
  });

  final int driverId;
  final double? averageKmPerLitre;
  final double? totalLitres;
  final double? totalCost;
  final double? totalDistanceKm;
  final List<Map<String, dynamic>> monthlyTrend;

  factory DriverFuelAnalysis.fromJson(Map<String, dynamic> map) {
    double? toDouble(dynamic value) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value);
      return null;
    }

    int toInt(dynamic value, {int fallback = 0}) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? fallback;
      return fallback;
    }

    List<Map<String, dynamic>> toTrend(dynamic raw) {
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return const <Map<String, dynamic>>[];
    }

    final payload = (map['data'] is Map)
        ? Map<String, dynamic>.from(map['data'] as Map)
        : map;

    return DriverFuelAnalysis(
      driverId: toInt(payload['driver_id'] ?? payload['id']),
      averageKmPerLitre: toDouble(
        payload['avg_km_per_litre'] ??
            payload['average_km_per_litre'] ??
            payload['efficiency'],
      ),
      totalLitres: toDouble(payload['total_litres']),
      totalCost: toDouble(payload['total_cost']),
      totalDistanceKm: toDouble(payload['total_distance_km']),
      monthlyTrend: toTrend(payload['monthly_trend'] ?? payload['trend']),
    );
  }
}

class FuelRepository {
  FuelRepository(
    this._dio,
    this._tokenStorage,
    this._queueBox,
    this._historyBox,
  );

  final Dio _dio;
  final TokenStorage _tokenStorage;
  final Box<Map> _queueBox;
  final Box<Map> _historyBox;

  Future<void> submitTripFuelLog({
    required int tripId,
    required double litres,
    required double cost,
    required double odometerKm,
    required bool fullTank,
    String? station,
    String? note,
  }) async {
    final payload = _buildPayload(
      scope: 'trip',
      tripId: tripId,
      litres: litres,
      cost: cost,
      odometerKm: odometerKm,
      fullTank: fullTank,
      station: station,
      note: note,
    );
    try {
      await _dio.post(
        Endpoints.tripFuelLogs(tripId),
        data: {'fuel_log': _apiFuelLog(payload)},
      );
      await _writeHistory(payload, FuelLogSyncStatus.synced);
    } on DioException catch (e) {
      if (e.response == null) {
        await _queueBox.add(payload);
        await _writeHistory(payload, FuelLogSyncStatus.queued);
        return;
      }
      await _writeHistory(payload, FuelLogSyncStatus.failed);
      rethrow;
    }
  }

  Future<void> submitVehicleFuelLog({
    required int vehicleId,
    required double litres,
    required double cost,
    required double odometerKm,
    required bool fullTank,
    String? station,
    String? note,
  }) async {
    final payload = _buildPayload(
      scope: 'vehicle',
      vehicleId: vehicleId,
      litres: litres,
      cost: cost,
      odometerKm: odometerKm,
      fullTank: fullTank,
      station: station,
      note: note,
    );
    try {
      await _dio.post(
        Endpoints.vehicleFuelLogs(vehicleId),
        data: {'fuel_log': _apiFuelLog(payload)},
      );
      await _writeHistory(payload, FuelLogSyncStatus.synced);
    } on DioException catch (e) {
      if (e.response == null) {
        await _queueBox.add(payload);
        await _writeHistory(payload, FuelLogSyncStatus.queued);
        return;
      }
      await _writeHistory(payload, FuelLogSyncStatus.failed);
      rethrow;
    }
  }

  Future<void> replayQueuedFuelLog(Map<String, dynamic> item) async {
    final scope = item['scope']?.toString() ?? 'trip';
    if (scope == 'vehicle') {
      final vehicleId = (item['vehicle_id'] as num?)?.toInt();
      if (vehicleId == null) return;
      await _dio.post(
        Endpoints.vehicleFuelLogs(vehicleId),
        data: {'fuel_log': _apiFuelLog(item)},
      );
      await _writeHistory(item, FuelLogSyncStatus.synced);
      return;
    }

    final tripId = (item['trip_id'] as num?)?.toInt();
    if (tripId == null) return;
    await _dio.post(
      Endpoints.tripFuelLogs(tripId),
      data: {'fuel_log': _apiFuelLog(item)},
    );
    await _writeHistory(item, FuelLogSyncStatus.synced);
  }

  Future<List<FuelLogSubmission>> recentSubmissions({
    int? tripId,
    int? vehicleId,
    int limit = 20,
  }) async {
    final list =
        _historyBox.values
            .map((e) => Map<String, dynamic>.from(e))
            .map(FuelLogSubmission.fromMap)
            .where((entry) {
              if (tripId != null) return entry.tripId == tripId;
              if (vehicleId != null) return entry.vehicleId == vehicleId;
              return true;
            })
            .toList()
          ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    if (list.length <= limit) return list;
    return list.sublist(0, limit);
  }

  Future<DriverFuelAnalysis> fetchDriverAnalysis({
    required int driverId,
  }) async {
    if (driverId <= 0) {
      throw Exception('Invalid driver id for fuel analysis.');
    }
    final role = await _currentRole();
    final canAccess =
        role == 'admin' ||
        role == 'dispatcher' ||
        role == 'supervisor' ||
        role == 'fleet_manager' ||
        role == 'manager';
    if (!canAccess) {
      throw Exception(
        'Role $role is not allowed to view driver fuel analysis.',
      );
    }
    final response = await _dio.get(Endpoints.fuelAnalysisDriver(driverId));
    return DriverFuelAnalysis.fromJson(
      response.data is Map<String, dynamic>
          ? response.data as Map<String, dynamic>
          : Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<String?> _currentRole() async {
    try {
      final token = await _tokenStorage.readToken();
      if (token == null || token.isEmpty) return null;
      final parts = token.split('.');
      if (parts.length < 2) return null;
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final claims = jsonDecode(payload) as Map<String, dynamic>;
      final role = claims['role']?.toString().toLowerCase();
      if (role != null && role.isNotEmpty) return role;
      final scope = claims['scp']?.toString().toLowerCase();
      if (scope == 'admin') return 'admin';
      if (scope == 'dispatcher') return 'dispatcher';
      if (scope == 'supervisor') return 'supervisor';
      if (scope == 'manager') return 'manager';
      if (scope == 'fleet_manager') return 'fleet_manager';
      return 'user';
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _buildPayload({
    required String scope,
    int? tripId,
    int? vehicleId,
    required double litres,
    required double cost,
    required double odometerKm,
    required bool fullTank,
    String? station,
    String? note,
  }) {
    return {
      'local_id': 'fuel_${DateTime.now().microsecondsSinceEpoch}',
      'scope': scope,
      if (tripId != null) 'trip_id': tripId,
      if (vehicleId != null) 'vehicle_id': vehicleId,
      'litres': litres,
      'cost': cost,
      'odometer_km': odometerKm,
      'full_tank': fullTank,
      if (station != null && station.trim().isNotEmpty)
        'station': station.trim(),
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      'recorded_at': DateTime.now().toIso8601String(),
      'created_at': DateTime.now().toIso8601String(),
    };
  }

  Map<String, dynamic> _apiFuelLog(Map<String, dynamic> payload) {
    return {
      'litres': payload['litres'],
      'cost': payload['cost'],
      'odometer_km': payload['odometer_km'],
      'full_tank': payload['full_tank'],
      if (payload['station'] != null) 'station': payload['station'],
      if (payload['note'] != null) 'note': payload['note'],
      if (payload['recorded_at'] != null) 'recorded_at': payload['recorded_at'],
    };
  }

  Future<void> _writeHistory(
    Map<String, dynamic> payload,
    FuelLogSyncStatus status,
  ) async {
    final record = Map<String, dynamic>.from(payload)
      ..['sync_status'] = status.name;
    await _historyBox.put(record['local_id'], record);
  }
}

final fuelRepositoryProvider = Provider<FuelRepository>((ref) {
  final dio = ref.read(dioProvider);
  final tokenStorage = ref.read(tokenStorageProvider);
  final queue = Hive.box<Map>(HiveBoxes.fuelLogsQueue);
  final history = Hive.box<Map>(HiveBoxes.fuelLogsHistory);
  return FuelRepository(dio, tokenStorage, queue, history);
});
