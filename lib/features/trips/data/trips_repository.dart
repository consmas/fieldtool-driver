import 'dart:io';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/errors/app_error.dart';
import '../../offline/hive_boxes.dart';
import '../domain/trip.dart';
import '../domain/trip_stop.dart';

class TripsRepository {
  TripsRepository(this._dio);

  final Dio _dio;

  Future<File> _maybeCompress(File file) async {
    try {
      final length = await file.length();
      if (length < 500 * 1024) {
        return file;
      }
      final dir = await getTemporaryDirectory();
      final name = file.path.split('/').last;
      final targetPath =
          '${dir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}_$name';
      final XFile? result = await FlutterImageCompress.compressAndGetFile(
        file.path,
        targetPath,
        quality: 70,
        minWidth: 1280,
        minHeight: 720,
        format: CompressFormat.jpeg,
      );
      return result == null ? file : File(result.path);
    } catch (_) {
      return file;
    }
  }

  Future<MultipartFile> createMultipartFile(XFile file) async {
    final raw = File(file.path);
    if (!raw.existsSync()) {
      throw AppError('Photo file not found.');
    }
    final processed = await _maybeCompress(raw);
    return MultipartFile.fromFile(
      processed.path,
      filename: processed.path.split('/').last,
    );
  }

  Future<List<Trip>> fetchAssignedTrips() async {
    final response = await _dio.get(Endpoints.trips);
    final data = response.data;
    final list = (data is List ? data : (data as Map)['data']) as List<dynamic>;
    return list.map((e) => Trip.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Trip> fetchTrip(int id) async {
    final response = await _dio.get(Endpoints.tripDetail(id));
    final data = response.data as Map<String, dynamic>;
    return Trip.fromJson(data);
  }

  Future<List<Map<String, dynamic>>> fetchTripEvidence(int tripId) async {
    dynamic data;
    try {
      final response = await _dio.get(Endpoints.tripEvidence(tripId));
      data = response.data;
    } on DioException catch (e) {
      // Some backend environments do not expose GET /trips/:id/evidence yet.
      // Treat 404 as "no evidence available" so UI can still load local/queued media.
      if (e.response?.statusCode == 404) {
        return const [];
      }
      rethrow;
    }

    List<dynamic>? pickList(dynamic value) {
      if (value is List) return value;
      if (value is Map) {
        final candidates = [
          value['data'],
          value['evidence'],
          value['evidences'],
          value['items'],
        ];
        for (final candidate in candidates) {
          if (candidate is List) return candidate;
        }
      }
      return null;
    }

    final list = pickList(data) ?? <dynamic>[];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> updateStatus(int id, String status) async {
    try {
      await _dio.post(Endpoints.tripStatus(id), data: {'status': status});
    } on DioException catch (e) {
      if (e.response?.statusCode == 422) {
        try {
          await _dio.patch(
            Endpoints.tripDetail(id),
            data: {
              'trip': {'status': status},
            },
          );
          return;
        } catch (_) {
          rethrow;
        }
      }
      if (e.response == null) {
        final box = Hive.box<Map>(HiveBoxes.statusQueue);
        await box.add({
          'trip_id': id,
          'status': status,
          'created_at': DateTime.now().toIso8601String(),
        });
        return;
      }
      rethrow;
    }
  }

  Future<void> replayStatus({
    required int tripId,
    required String status,
  }) async {
    try {
      await _dio.post(Endpoints.tripStatus(tripId), data: {'status': status});
    } on DioException catch (e) {
      if (e.response?.statusCode == 422) {
        await _dio.patch(
          Endpoints.tripDetail(tripId),
          data: {
            'trip': {'status': status},
          },
        );
        return;
      }
      rethrow;
    }
  }

  Future<void> updateTrip(int id, Map<String, dynamic> fields) async {
    await _dio.patch(Endpoints.tripDetail(id), data: {'trip': fields});
  }

  Future<List<TripStop>> fetchTripStops(int tripId) async {
    final response = await _dio.get(Endpoints.tripStops(tripId));
    final data = response.data;
    final list = (data is List ? data : (data as Map)['data']) as List<dynamic>;
    return list
        .map((e) => TripStop.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> updateTripStop(
    int tripId,
    int stopId,
    Map<String, dynamic> fields,
  ) async {
    await _dio.patch(
      Endpoints.tripStop(tripId, stopId),
      data: {'stop': fields},
    );
  }

  Future<void> uploadTripAttachments({
    required int tripId,
    XFile? clientRepSignature,
    XFile? proofOfFuelling,
    XFile? inspectorSignature,
    XFile? securitySignature,
    XFile? driverSignature,
  }) async {
    final formMap = <String, dynamic>{};

    if (clientRepSignature != null) {
      formMap['attachments[client_rep_signature]'] = await createMultipartFile(
        clientRepSignature,
      );
    }
    if (proofOfFuelling != null) {
      formMap['attachments[proof_of_fuelling]'] = await createMultipartFile(
        proofOfFuelling,
      );
    }
    if (inspectorSignature != null) {
      formMap['attachments[inspector_signature]'] = await createMultipartFile(
        inspectorSignature,
      );
    }
    if (securitySignature != null) {
      formMap['attachments[security_signature]'] = await createMultipartFile(
        securitySignature,
      );
    }
    if (driverSignature != null) {
      formMap['attachments[driver_signature]'] = await createMultipartFile(
        driverSignature,
      );
    }

    if (formMap.isEmpty) {
      return;
    }

    final formData = FormData.fromMap(formMap);
    try {
      await _dio.patch(Endpoints.tripAttachments(tripId), data: formData);
    } on DioException catch (e) {
      if (e.response == null) {
        final box = Hive.box<Map>(HiveBoxes.evidenceQueue);
        await box.add({
          'type': 'attachments',
          'trip_id': tripId,
          'client_rep_signature_path': clientRepSignature?.path,
          'proof_of_fuelling_path': proofOfFuelling?.path,
          'inspector_signature_path': inspectorSignature?.path,
          'security_signature_path': securitySignature?.path,
          'driver_signature_path': driverSignature?.path,
          'created_at': DateTime.now().toIso8601String(),
        });
        return;
      }
      rethrow;
    }
  }

  Future<void> uploadEvidence({
    required int tripId,
    required String kind,
    required XFile photo,
    String? note,
    double? lat,
    double? lng,
    DateTime? recordedAt,
  }) async {
    final formData = FormData.fromMap({
      'evidence[kind]': kind,
      'evidence[photo]': await createMultipartFile(photo),
      if (note != null && note.isNotEmpty) 'evidence[note]': note,
      if (lat case final latValue?) 'evidence[lat]': latValue,
      if (lng case final lngValue?) 'evidence[lng]': lngValue,
      if (recordedAt != null)
        'evidence[recorded_at]': recordedAt.toIso8601String(),
    });
    try {
      await _dio.post(Endpoints.tripEvidence(tripId), data: formData);
    } on DioException catch (e) {
      if (e.response == null) {
        final box = Hive.box<Map>(HiveBoxes.evidenceQueue);
        await box.add({
          'type': 'evidence',
          'trip_id': tripId,
          'kind': kind,
          'photo_path': photo.path,
          'note': note,
          'lat': lat,
          'lng': lng,
          'recorded_at': recordedAt?.toIso8601String(),
          'created_at': DateTime.now().toIso8601String(),
        });
        return;
      }
      rethrow;
    }
  }

  Future<void> replayQueuedMedia(Map<String, dynamic> item) async {
    final type = item['type']?.toString();
    if (type == 'attachments') {
      final tripId = item['trip_id'] as int;
      final formMap = <String, dynamic>{};

      Future<void> addIfPresent(String key, String fieldName) async {
        final path = item[key]?.toString();
        if (path == null || path.isEmpty) return;
        final file = File(path);
        if (!await file.exists()) return;
        formMap[fieldName] = await createMultipartFile(XFile(path));
      }

      await addIfPresent(
        'client_rep_signature_path',
        'attachments[client_rep_signature]',
      );
      await addIfPresent(
        'proof_of_fuelling_path',
        'attachments[proof_of_fuelling]',
      );
      await addIfPresent(
        'inspector_signature_path',
        'attachments[inspector_signature]',
      );
      await addIfPresent(
        'security_signature_path',
        'attachments[security_signature]',
      );
      await addIfPresent(
        'driver_signature_path',
        'attachments[driver_signature]',
      );

      if (formMap.isEmpty) return;
      await _dio.patch(
        Endpoints.tripAttachments(tripId),
        data: FormData.fromMap(formMap),
      );
      return;
    }

    if (type == 'evidence') {
      final tripId = item['trip_id'] as int;
      final kind = item['kind']?.toString();
      final photoPath = item['photo_path']?.toString();
      if (kind == null ||
          kind.isEmpty ||
          photoPath == null ||
          photoPath.isEmpty) {
        return;
      }
      final photoFile = File(photoPath);
      if (!await photoFile.exists()) return;

      final formData = FormData.fromMap({
        'evidence[kind]': kind,
        'evidence[photo]': await createMultipartFile(XFile(photoPath)),
        if (item['note'] != null && item['note'].toString().isNotEmpty)
          'evidence[note]': item['note'].toString(),
        if (item['lat'] != null) 'evidence[lat]': item['lat'],
        if (item['lng'] != null) 'evidence[lng]': item['lng'],
        if (item['recorded_at'] != null)
          'evidence[recorded_at]': item['recorded_at'].toString(),
      });
      await _dio.post(Endpoints.tripEvidence(tripId), data: formData);
    }
  }

  Future<void> updatePreTripFields(
    int tripId,
    Map<String, dynamic> fields,
  ) async {
    final formData = FormData.fromMap(fields);
    await _dio.patch(Endpoints.tripPreTrip(tripId), data: formData);
  }

  Future<void> uploadOdometerStart({
    required int tripId,
    required double valueKm,
    required XFile photo,
    required double lat,
    required double lng,
    String? note,
  }) async {
    final formData = FormData.fromMap({
      'odometer[value_km]': valueKm,
      'odometer[lat]': lat,
      'odometer[lng]': lng,
      'odometer[captured_at]': DateTime.now().toIso8601String(),
      'odometer[note]': note,
      'odometer[photo]': await createMultipartFile(photo),
    });

    await _dio.post(Endpoints.tripOdometerStart(tripId), data: formData);
  }

  Future<void> uploadOdometerEnd({
    required int tripId,
    required double valueKm,
    required XFile photo,
    required double lat,
    required double lng,
    String? note,
  }) async {
    final formData = FormData.fromMap({
      'odometer[value_km]': valueKm,
      'odometer[lat]': lat,
      'odometer[lng]': lng,
      'odometer[captured_at]': DateTime.now().toIso8601String(),
      'odometer[note]': note,
      'odometer[photo]': await createMultipartFile(photo),
    });

    await _dio.post(Endpoints.tripOdometerEnd(tripId), data: formData);
  }

  Future<Map<String, dynamic>?> fetchPreTrip(int tripId) async {
    try {
      final response = await _dio.get(Endpoints.tripPreTrip(tripId));
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  Future<void> submitPreTrip({
    required int tripId,
    required double odometerValueKm,
    XFile? odometerPhoto,
    XFile? inspectorSignature,
    XFile? inspectorPhoto,
    required bool brakes,
    required bool tyres,
    required bool lights,
    required bool mirrors,
    required bool horn,
    required bool fuelSufficient,
    required bool accepted,
    double? lat,
    double? lng,
    DateTime? capturedAt,
    Map<String, dynamic>? coreChecklist,
    bool update = false,
  }) async {
    final formMap = <String, dynamic>{
      'pre_trip[odometer_value_km]': odometerValueKm,
      'pre_trip[brakes]': brakes,
      'pre_trip[tyres]': tyres,
      'pre_trip[lights]': lights,
      'pre_trip[mirrors]': mirrors,
      'pre_trip[horn]': horn,
      'pre_trip[fuel_sufficient]': fuelSufficient,
      'pre_trip[accepted]': accepted,
    };
    if (odometerPhoto != null) {
      formMap['pre_trip[odometer_photo]'] = await createMultipartFile(
        odometerPhoto,
      );
    }
    if (inspectorSignature != null) {
      formMap['pre_trip[inspector_signature]'] = await createMultipartFile(
        inspectorSignature,
      );
    }
    if (inspectorPhoto != null) {
      formMap['pre_trip[inspector_photo]'] = await createMultipartFile(
        inspectorPhoto,
      );
    }

    if (capturedAt != null) {
      formMap['pre_trip[odometer_captured_at]'] = capturedAt.toIso8601String();
    }
    if (lat != null) formMap['pre_trip[odometer_lat]'] = lat;
    if (lng != null) formMap['pre_trip[odometer_lng]'] = lng;
    if (accepted) {
      formMap['pre_trip[accepted_at]'] = DateTime.now().toIso8601String();
    }
    if (coreChecklist != null && coreChecklist.isNotEmpty) {
      formMap['pre_trip[core_checklist]'] = coreChecklist;
      formMap['pre_trip[core_checklist_json]'] = jsonEncode(coreChecklist);
    }

    final formData = FormData.fromMap(formMap);
    try {
      if (update) {
        await _dio.patch(Endpoints.tripPreTrip(tripId), data: formData);
      } else {
        await _dio.post(Endpoints.tripPreTrip(tripId), data: formData);
      }
    } on DioException catch (e) {
      if (e.response == null) {
        final box = Hive.box<Map>(HiveBoxes.preTripQueue);
        await box.add({
          'trip_id': tripId,
          'odometer_value_km': odometerValueKm,
          'odometer_photo_path': odometerPhoto?.path,
          'inspector_signature_path': inspectorSignature?.path,
          'inspector_photo_path': inspectorPhoto?.path,
          'brakes': brakes,
          'tyres': tyres,
          'lights': lights,
          'mirrors': mirrors,
          'horn': horn,
          'fuel_sufficient': fuelSufficient,
          'accepted': accepted,
          'odometer_lat': lat,
          'odometer_lng': lng,
          'odometer_captured_at': capturedAt?.toIso8601String(),
          'core_checklist_json': coreChecklist == null
              ? null
              : jsonEncode(coreChecklist),
          'core_checklist': coreChecklist,
          'update': update,
          'created_at': DateTime.now().toIso8601String(),
        });
        return;
      }
      rethrow;
    }
  }

  Future<void> replayQueuedPreTrip(Map<String, dynamic> item) async {
    final tripId = item['trip_id'] as int;
    final formMap = <String, dynamic>{
      'pre_trip[odometer_value_km]': item['odometer_value_km'],
      'pre_trip[brakes]': item['brakes'],
      'pre_trip[tyres]': item['tyres'],
      'pre_trip[lights]': item['lights'],
      'pre_trip[mirrors]': item['mirrors'],
      'pre_trip[horn]': item['horn'],
      'pre_trip[fuel_sufficient]': item['fuel_sufficient'],
      'pre_trip[accepted]': item['accepted'],
    };

    Future<void> addIfPresent(String queueKey, String formKey) async {
      final path = item[queueKey]?.toString();
      if (path == null || path.isEmpty) return;
      final file = File(path);
      if (!await file.exists()) return;
      formMap[formKey] = await createMultipartFile(XFile(path));
    }

    await addIfPresent('odometer_photo_path', 'pre_trip[odometer_photo]');
    await addIfPresent(
      'inspector_signature_path',
      'pre_trip[inspector_signature]',
    );
    await addIfPresent('inspector_photo_path', 'pre_trip[inspector_photo]');

    if (item['odometer_captured_at'] != null) {
      formMap['pre_trip[odometer_captured_at]'] = item['odometer_captured_at']
          .toString();
    }
    if (item['odometer_lat'] != null) {
      formMap['pre_trip[odometer_lat]'] = item['odometer_lat'];
    }
    if (item['odometer_lng'] != null) {
      formMap['pre_trip[odometer_lng]'] = item['odometer_lng'];
    }
    if (item['accepted'] == true) {
      formMap['pre_trip[accepted_at]'] = DateTime.now().toIso8601String();
    }
    final coreChecklistObject = item['core_checklist'];
    if (coreChecklistObject is Map && coreChecklistObject.isNotEmpty) {
      formMap['pre_trip[core_checklist]'] = Map<String, dynamic>.from(
        coreChecklistObject,
      );
    }
    final coreChecklistJson = item['core_checklist_json']?.toString();
    if (coreChecklistJson != null && coreChecklistJson.isNotEmpty) {
      formMap['pre_trip[core_checklist_json]'] = coreChecklistJson;
    }

    final formData = FormData.fromMap(formMap);
    final update = item['update'] == true;
    if (update) {
      await _dio.patch(Endpoints.tripPreTrip(tripId), data: formData);
    } else {
      await _dio.post(Endpoints.tripPreTrip(tripId), data: formData);
    }
  }
}

final tripsRepositoryProvider = Provider<TripsRepository>((ref) {
  final dio = ref.read(dioProvider);
  return TripsRepository(dio);
});
