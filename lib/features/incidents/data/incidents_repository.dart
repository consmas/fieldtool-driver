import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../offline/hive_boxes.dart';
import '../../trips/data/trips_repository.dart';

class DriverIncident {
  DriverIncident({
    required this.id,
    required this.incidentNo,
    required this.title,
    required this.incidentType,
    required this.severity,
    required this.status,
    required this.createdAt,
  });

  final int id;
  final String incidentNo;
  final String title;
  final String incidentType;
  final String severity;
  final String status;
  final DateTime createdAt;

  factory DriverIncident.fromJson(Map<String, dynamic> map) {
    int toInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    DateTime toDate(dynamic value) {
      if (value is String) {
        return DateTime.tryParse(value)?.toLocal() ?? DateTime.now();
      }
      return DateTime.now();
    }

    return DriverIncident(
      id: toInt(map['id']),
      incidentNo:
          (map['incident_no'] ?? map['reference'] ?? '#${toInt(map['id'])}')
              .toString(),
      title: (map['title'] ?? map['summary'] ?? 'Incident').toString(),
      incidentType:
          (map['incident_type'] ?? map['type'] ?? 'general').toString(),
      severity: (map['severity'] ?? 'medium').toString(),
      status: (map['status'] ?? 'open').toString(),
      createdAt: toDate(map['created_at'] ?? map['incident_date']),
    );
  }
}

class IncidentsRepository {
  IncidentsRepository(
    this._dio,
    this._tripsRepository,
    this._draftQueueBox,
    this._evidenceQueueBox,
  );

  final Dio _dio;
  final TripsRepository _tripsRepository;
  final Box<Map> _draftQueueBox;
  final Box<Map> _evidenceQueueBox;

  List<Map<String, dynamic>> _pickList(dynamic raw) {
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (raw is Map) {
      final data = raw['data'] ?? raw['items'] ?? raw['incidents'];
      if (data is List) {
        return data
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    }
    return const <Map<String, dynamic>>[];
  }

  Map<String, dynamic> _pickMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const <String, dynamic>{};
  }

  Future<List<DriverIncident>> fetchMyIncidents() async {
    final response = await _dio.get(Endpoints.meIncidents);
    final list = _pickList(response.data).map(DriverIncident.fromJson).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Future<int?> createIncident({
    String? tripId,
    String? vehicleId,
    required String incidentType,
    required String severity,
    required String title,
    required String description,
    required bool injuryReported,
    required bool vehicleDrivable,
    String? locationText,
    double? lat,
    double? lng,
    DateTime? incidentDate,
  }) async {
    final payload = <String, dynamic>{
      'incident[type]': incidentType,
      'incident[severity]': severity,
      'incident[title]': title,
      'incident[description]': description,
      'incident[injury_reported]': injuryReported,
      'incident[vehicle_drivable]': vehicleDrivable,
      'incident[incident_date]':
          (incidentDate ?? DateTime.now()).toIso8601String(),
      if (tripId != null && tripId.isNotEmpty) 'incident[trip_id]': tripId,
      if (vehicleId != null && vehicleId.isNotEmpty)
        'incident[vehicle_id]': vehicleId,
      if (locationText != null && locationText.isNotEmpty)
        'incident[location_text]': locationText,
      if (lat != null) 'incident[lat]': lat,
      if (lng != null) 'incident[lng]': lng,
    };

    try {
      final response = await _dio.post(
        Endpoints.meIncidents,
        data: FormData.fromMap(payload),
      );
      final map = _pickMap(response.data);
      final data = _pickMap(map['data'] ?? map['incident'] ?? map);
      final id = data['id'];
      if (id is int) return id;
      if (id is num) return id.toInt();
      if (id is String) return int.tryParse(id);
      return null;
    } on DioException catch (e) {
      if (e.response == null) {
        await _draftQueueBox.add({
          'trip_id': tripId,
          'vehicle_id': vehicleId,
          'incident_type': incidentType,
          'severity': severity,
          'title': title,
          'description': description,
          'injury_reported': injuryReported,
          'vehicle_drivable': vehicleDrivable,
          'location_text': locationText,
          'lat': lat,
          'lng': lng,
          'incident_date':
              (incidentDate ?? DateTime.now()).toIso8601String(),
          'created_at': DateTime.now().toIso8601String(),
        });
        return null;
      }
      rethrow;
    }
  }

  Future<void> uploadIncidentEvidence({
    required int incidentId,
    required String category,
    required XFile file,
    String? note,
  }) async {
    final form = FormData.fromMap({
      'evidence[category]': category,
      'evidence[file]': await _tripsRepository.createMultipartFile(file),
      if (note != null && note.isNotEmpty) 'evidence[note]': note,
    });
    try {
      await _dio.post(Endpoints.meIncidentEvidence(incidentId), data: form);
    } on DioException catch (e) {
      if (e.response == null) {
        await _evidenceQueueBox.add({
          'incident_id': incidentId,
          'category': category,
          'file_path': file.path,
          'note': note,
          'created_at': DateTime.now().toIso8601String(),
        });
        return;
      }
      rethrow;
    }
  }

  Future<void> replayQueuedIncidentDraft(Map<String, dynamic> item) async {
    final payload = {
      'incident[type]': item['incident_type'],
      'incident[severity]': item['severity'],
      'incident[title]': item['title'],
      'incident[description]': item['description'],
      'incident[injury_reported]': item['injury_reported'] == true,
      'incident[vehicle_drivable]': item['vehicle_drivable'] == true,
      'incident[incident_date]': item['incident_date'],
      if (item['trip_id'] != null) 'incident[trip_id]': item['trip_id'],
      if (item['vehicle_id'] != null) 'incident[vehicle_id]': item['vehicle_id'],
      if (item['location_text'] != null)
        'incident[location_text]': item['location_text'],
      if (item['lat'] != null) 'incident[lat]': item['lat'],
      if (item['lng'] != null) 'incident[lng]': item['lng'],
    };
    await _dio.post(Endpoints.meIncidents, data: FormData.fromMap(payload));
  }

  Future<void> replayQueuedIncidentEvidence(Map<String, dynamic> item) async {
    final incidentId = (item['incident_id'] as num?)?.toInt();
    final path = item['file_path']?.toString();
    if (incidentId == null || path == null || path.isEmpty) return;
    final file = File(path);
    if (!await file.exists()) return;
    final form = FormData.fromMap({
      'evidence[category]': (item['category'] ?? 'scene').toString(),
      'evidence[file]': await _tripsRepository.createMultipartFile(XFile(path)),
      if (item['note'] != null && item['note'].toString().isNotEmpty)
        'evidence[note]': item['note'].toString(),
    });
    await _dio.post(Endpoints.meIncidentEvidence(incidentId), data: form);
  }
}

final incidentsRepositoryProvider = Provider<IncidentsRepository>((ref) {
  final dio = ref.read(dioProvider);
  final tripsRepository = ref.read(tripsRepositoryProvider);
  final draftQueue = Hive.box<Map>(HiveBoxes.incidentDraftsQueue);
  final evidenceQueue = Hive.box<Map>(HiveBoxes.incidentEvidenceQueue);
  return IncidentsRepository(dio, tripsRepository, draftQueue, evidenceQueue);
});
