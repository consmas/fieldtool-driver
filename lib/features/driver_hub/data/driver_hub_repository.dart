import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/auth/token_storage.dart';
import '../../notifications/data/notifications_repository.dart';
import '../../offline/hive_boxes.dart';
import '../../trips/data/trips_repository.dart';

class DriverHubLoad<T> {
  DriverHubLoad({
    required this.data,
    required this.fromCache,
    required this.lastSyncAt,
  });

  final T data;
  final bool fromCache;
  final DateTime? lastSyncAt;
}

class DriverScorePoint {
  DriverScorePoint({
    required this.label,
    required this.overall,
    required this.dimensions,
  });
  final String label;
  final double overall;
  final Map<String, double> dimensions;
}

class DriverProfileData {
  DriverProfileData({
    required this.driverId,
    required this.name,
    required this.tier,
    required this.overallScore,
    required this.trend,
    required this.vehicleId,
    required this.dimensions,
  });

  final int driverId;
  final String name;
  final String tier;
  final double overallScore;
  final String trend;
  final int? vehicleId;
  final Map<String, double> dimensions;

  factory DriverProfileData.fromJson(Map<String, dynamic> map) {
    int toInt(dynamic v, {int fallback = 0}) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? fallback;
      return fallback;
    }

    double toDouble(dynamic v, {double fallback = 0}) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? fallback;
      return fallback;
    }

    Map<String, double> parseDimensions(dynamic raw) {
      if (raw is Map) {
        return raw.map((k, v) => MapEntry(k.toString(), toDouble(v)));
      }
      return <String, double>{
        'safety': toDouble(map['safety_score']),
        'efficiency': toDouble(map['efficiency_score']),
        'compliance': toDouble(map['compliance_score']),
        'timeliness': toDouble(map['timeliness_score']),
        'professionalism': toDouble(map['professionalism_score']),
      };
    }

    return DriverProfileData(
      driverId: toInt(map['driver_id'] ?? map['user_id'] ?? map['id']),
      name: (map['name'] ?? map['driver_name'] ?? 'Driver').toString(),
      tier: (map['tier'] ?? map['current_tier'] ?? map['score_tier'] ?? 'bronze')
          .toString(),
      overallScore: toDouble(
        map['overall_score'] ?? map['current_score'] ?? map['score'],
      ),
      trend: (map['trend'] ?? 'stable').toString(),
      vehicleId: (() {
        final v =
            map['vehicle_id'] ??
            (map['vehicle'] is Map ? (map['vehicle'] as Map)['id'] : null) ??
            map['assigned_vehicle_id'];
        if (v == null) return null;
        if (v is int) return v;
        if (v is num) return v.toInt();
        if (v is String) return int.tryParse(v);
        return null;
      })(),
      dimensions: parseDimensions(map['dimensions']),
    );
  }

  Map<String, dynamic> toJson() => {
    'driver_id': driverId,
    'name': name,
    'tier': tier,
    'overall_score': overallScore,
    'trend': trend,
    'vehicle_id': vehicleId,
    'dimensions': dimensions,
  };
}

class DriverRank {
  DriverRank({required this.rank, required this.fleetSize});
  final int rank;
  final int fleetSize;

  factory DriverRank.fromJson(Map<String, dynamic> map) {
    int toInt(dynamic v, {int fallback = 0}) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? fallback;
      return fallback;
    }

    return DriverRank(
      rank: toInt(map['rank'] ?? map['position']),
      fleetSize: toInt(map['fleet_size'] ?? map['total_drivers']),
    );
  }

  Map<String, dynamic> toJson() => {'rank': rank, 'fleet_size': fleetSize};
}

class DriverBadge {
  DriverBadge({
    required this.id,
    required this.title,
    required this.description,
    this.earnedAt,
  });
  final int id;
  final String title;
  final String description;
  final DateTime? earnedAt;

  factory DriverBadge.fromJson(Map<String, dynamic> map) {
    int toInt(dynamic v, {int fallback = 0}) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? fallback;
      return fallback;
    }

    return DriverBadge(
      id: toInt(map['id']),
      title: (map['title'] ?? map['name'] ?? 'Badge').toString(),
      description: (map['description'] ?? '').toString(),
      earnedAt: DateTime.tryParse(
        (map['earned_at'] ?? '').toString(),
      )?.toLocal(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'earned_at': earnedAt?.toIso8601String(),
  };
}

class ImprovementTip {
  ImprovementTip({
    required this.dimension,
    required this.title,
    required this.body,
  });
  final String dimension;
  final String title;
  final String body;

  factory ImprovementTip.fromJson(Map<String, dynamic> map) {
    return ImprovementTip(
      dimension: (map['dimension'] ?? map['category'] ?? 'general').toString(),
      title: (map['title'] ?? 'Tip').toString(),
      body: (map['body'] ?? map['message'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'dimension': dimension,
    'title': title,
    'body': body,
  };
}

enum DriverDocumentStatus { active, expiringSoon, expired, unknown }

enum DriverVerificationStatus { unverified, verified, rejected, unknown }

class DriverDocumentItem {
  DriverDocumentItem({
    required this.id,
    required this.type,
    required this.title,
    this.number,
    this.issuedDate,
    this.expiryDate,
    required this.status,
    required this.verificationStatus,
    this.documentUrl,
  });

  final int id;
  final String type;
  final String title;
  final String? number;
  final DateTime? issuedDate;
  final DateTime? expiryDate;
  final DriverDocumentStatus status;
  final DriverVerificationStatus verificationStatus;
  final String? documentUrl;

  int? get daysToExpiry {
    if (expiryDate == null) return null;
    final now = DateTime.now();
    return DateTime(
      expiryDate!.year,
      expiryDate!.month,
      expiryDate!.day,
    ).difference(DateTime(now.year, now.month, now.day)).inDays;
  }

  factory DriverDocumentItem.fromJson(Map<String, dynamic> map) {
    int toInt(dynamic v, {int fallback = 0}) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? fallback;
      return fallback;
    }

    DriverDocumentStatus parseStatus(String v) {
      final x = v.toLowerCase();
      if (x == 'active') return DriverDocumentStatus.active;
      if (x == 'expiring_soon' || x == 'expiring') {
        return DriverDocumentStatus.expiringSoon;
      }
      if (x == 'expired') return DriverDocumentStatus.expired;
      return DriverDocumentStatus.unknown;
    }

    DriverVerificationStatus parseVerification(String v) {
      final x = v.toLowerCase();
      if (x == 'verified') return DriverVerificationStatus.verified;
      if (x == 'rejected') return DriverVerificationStatus.rejected;
      if (x == 'unverified') return DriverVerificationStatus.unverified;
      return DriverVerificationStatus.unknown;
    }

    return DriverDocumentItem(
      id: toInt(map['id']),
      type: (map['document_type'] ?? map['type'] ?? 'document').toString(),
      title: (map['title'] ?? map['name'] ?? map['document_type'] ?? 'Document')
          .toString(),
      number: map['document_number']?.toString(),
      issuedDate: DateTime.tryParse(
        (map['issued_date'] ?? '').toString(),
      )?.toLocal(),
      expiryDate: DateTime.tryParse(
        (map['expiry_date'] ?? '').toString(),
      )?.toLocal(),
      status: parseStatus((map['status'] ?? '').toString()),
      verificationStatus: parseVerification(
        (map['verification_status'] ?? 'unverified').toString(),
      ),
      documentUrl: map['document_url']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'document_type': type,
    'title': title,
    'document_number': number,
    'issued_date': issuedDate?.toIso8601String(),
    'expiry_date': expiryDate?.toIso8601String(),
    'status': status.name,
    'verification_status': verificationStatus.name,
    'document_url': documentUrl,
  };
}

class VehicleInsuranceBlock {
  VehicleInsuranceBlock({
    required this.vehicleName,
    required this.plate,
    required this.vehicleType,
    this.provider,
    this.policyNumber,
    this.issuedDate,
    this.expiryDate,
    this.coverageAmount,
    this.notes,
    this.documentUrl,
  });

  final String vehicleName;
  final String plate;
  final String vehicleType;
  final String? provider;
  final String? policyNumber;
  final DateTime? issuedDate;
  final DateTime? expiryDate;
  final String? coverageAmount;
  final String? notes;
  final String? documentUrl;

  bool get isExpired =>
      expiryDate != null && expiryDate!.isBefore(DateTime.now());
  bool get isExpiringSoon =>
      expiryDate != null &&
      !isExpired &&
      expiryDate!.difference(DateTime.now()).inDays <= 30;

  factory VehicleInsuranceBlock.fromJson(Map<String, dynamic> map) {
    final insurance = (map['insurance'] is Map)
        ? Map<String, dynamic>.from(map['insurance'] as Map)
        : <String, dynamic>{};
    return VehicleInsuranceBlock(
      vehicleName: (map['name'] ?? map['vehicle_name'] ?? 'Vehicle').toString(),
      plate: (map['plate'] ?? map['license_plate'] ?? '—').toString(),
      vehicleType: (map['type'] ?? map['vehicle_type'] ?? '—').toString(),
      provider: (insurance['provider'] ?? map['insurance_provider'])
          ?.toString(),
      policyNumber:
          (insurance['policy_number'] ?? map['insurance_policy_number'])
              ?.toString(),
      issuedDate: DateTime.tryParse(
        (insurance['issued_date'] ?? map['insurance_issued_date'] ?? '')
            .toString(),
      )?.toLocal(),
      expiryDate: DateTime.tryParse(
        (insurance['expiry_date'] ?? map['insurance_expiry_date'] ?? '')
            .toString(),
      )?.toLocal(),
      coverageAmount:
          (insurance['coverage_amount'] ?? map['insurance_coverage_amount'])
              ?.toString(),
      notes: (insurance['notes'] ?? map['insurance_notes'])?.toString(),
      documentUrl: (insurance['document_url'] ?? map['insurance_document_url'])
          ?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'vehicle_name': vehicleName,
    'plate': plate,
    'vehicle_type': vehicleType,
    'insurance': {
      'provider': provider,
      'policy_number': policyNumber,
      'issued_date': issuedDate?.toIso8601String(),
      'expiry_date': expiryDate?.toIso8601String(),
      'coverage_amount': coverageAmount,
      'notes': notes,
      'document_url': documentUrl,
    },
  };
}

class DriverHubRepository {
  DriverHubRepository(
    this._dio,
    this._cache,
    this._docQueue,
    this._tokenStorage,
    this._tripsRepository,
    this._notificationsRepository,
  );

  final Dio _dio;
  final Box<Map> _cache;
  final Box<Map> _docQueue;
  final TokenStorage _tokenStorage;
  final TripsRepository _tripsRepository;
  final NotificationsRepository _notificationsRepository;

  static const _kProfile = 'profile';
  static const _kScores = 'scores';
  static const _kRank = 'rank';
  static const _kBadges = 'badges';
  static const _kTips = 'tips';
  static const _kDocs = 'docs';
  static const _kVehicle = 'vehicle';

  Future<DriverHubLoad<DriverProfileData>> fetchProfile() async {
    try {
      return await _fetchAndCache(
        key: _kProfile,
        request: () => _dio.get(Endpoints.meProfile),
        parser: (data) => DriverProfileData.fromJson(_pickMap(data)),
      );
    } on DioException {
      final cached = _cache.get(_kProfile);
      if (cached != null) {
        final payload = cached['payload'];
        final storedAt = DateTime.tryParse(
          (cached['stored_at'] ?? '').toString(),
        )?.toLocal();
        return DriverHubLoad(
          data: DriverProfileData.fromJson(_pickMap(payload)),
          fromCache: true,
          lastSyncAt: storedAt,
        );
      }
      final fallback = await _fallbackProfileFromToken();
      if (fallback != null) {
        await _cache.put(_kProfile, {
          'payload': fallback.toJson(),
          'stored_at': DateTime.now().toIso8601String(),
        });
        return DriverHubLoad(
          data: fallback,
          fromCache: true,
          lastSyncAt: DateTime.now(),
        );
      }
      rethrow;
    }
  }

  Future<DriverHubLoad<List<DriverScorePoint>>> fetchScores() async {
    return _fetchAndCache(
      key: _kScores,
      request: () => _dio.get(Endpoints.meScores),
      parser: (data) => _pickList(data).map((e) {
        final label = (e['label'] ?? e['period'] ?? e['week'] ?? 'Period')
            .toString();
        final overall = _toDouble(e['overall_score'] ?? e['score']);
        final dimsRaw = e['dimensions'] is Map
            ? Map<String, dynamic>.from(e['dimensions'] as Map)
            : <String, dynamic>{};
        final dims = <String, double>{
          'safety': _toDouble(dimsRaw['safety'] ?? e['safety']),
          'efficiency': _toDouble(dimsRaw['efficiency'] ?? e['efficiency']),
          'compliance': _toDouble(dimsRaw['compliance'] ?? e['compliance']),
          'timeliness': _toDouble(dimsRaw['timeliness'] ?? e['timeliness']),
          'professionalism': _toDouble(
            dimsRaw['professionalism'] ?? e['professionalism'],
          ),
        };
        return DriverScorePoint(
          label: label,
          overall: overall,
          dimensions: dims,
        );
      }).toList(),
    );
  }

  Future<DriverHubLoad<DriverRank>> fetchRank() async {
    return _fetchAndCache(
      key: _kRank,
      request: () => _dio.get(Endpoints.meRank),
      parser: (data) => DriverRank.fromJson(_pickMap(data)),
    );
  }

  Future<DriverHubLoad<List<DriverBadge>>> fetchBadges() async {
    return _fetchAndCache(
      key: _kBadges,
      request: () => _dio.get(Endpoints.meBadges),
      parser: (data) => _pickList(data).map(DriverBadge.fromJson).toList(),
    );
  }

  Future<DriverHubLoad<List<ImprovementTip>>> fetchImprovementTips() async {
    return _fetchAndCache(
      key: _kTips,
      request: () => _dio.get(Endpoints.meImprovementTips),
      parser: (data) => _pickList(data).map(ImprovementTip.fromJson).toList(),
    );
  }

  Future<DriverHubLoad<List<DriverDocumentItem>>> fetchDocuments() async {
    return _fetchAndCache(
      key: _kDocs,
      request: () => _dio.get(Endpoints.meDocuments),
      parser: (data) =>
          _pickList(data).map(DriverDocumentItem.fromJson).toList(),
    );
  }

  Future<DriverHubLoad<VehicleInsuranceBlock?>> fetchAssignedVehicle() async {
    final profile = await fetchProfile();
    final vehicleId = profile.data.vehicleId;
    if (vehicleId == null) {
      return DriverHubLoad<VehicleInsuranceBlock?>(
        data: null,
        fromCache: profile.fromCache,
        lastSyncAt: profile.lastSyncAt,
      );
    }

    return _fetchAndCache(
      key: _kVehicle,
      request: () => _dio.get(Endpoints.vehicleDetail(vehicleId)),
      parser: (data) => VehicleInsuranceBlock.fromJson(_pickMap(data)),
    );
  }

  Future<void> uploadMyDocument({
    required String type,
    required String title,
    required DateTime expiryDate,
    DateTime? issuedDate,
    String? number,
    required XFile file,
  }) async {
    final multipart = await _tripsRepository.createMultipartFile(file);
    final form = FormData.fromMap({
      'document[type]': type,
      'document[title]': title,
      'document[expiry_date]': expiryDate.toIso8601String(),
      if (issuedDate != null)
        'document[issued_date]': issuedDate.toIso8601String(),
      if (number != null && number.trim().isNotEmpty)
        'document[number]': number.trim(),
      'document[file]': multipart,
    });
    try {
      await _dio.post(Endpoints.meDocuments, data: form);
      await _dio.get(Endpoints.meDocuments);
    } on DioException catch (e) {
      if (e.response == null) {
        await _docQueue.add({
          'type': type,
          'title': title,
          'expiry_date': expiryDate.toIso8601String(),
          'issued_date': issuedDate?.toIso8601String(),
          'number': number,
          'file_path': file.path,
          'created_at': DateTime.now().toIso8601String(),
        });
        return;
      }
      rethrow;
    }
  }

  Future<void> replayQueuedDocumentUpload(Map<String, dynamic> item) async {
    final path = item['file_path']?.toString();
    if (path == null || path.isEmpty) return;
    final file = File(path);
    if (!await file.exists()) return;
    final multipart = await _tripsRepository.createMultipartFile(XFile(path));
    final form = FormData.fromMap({
      'document[type]': item['type'],
      'document[title]': item['title'],
      'document[expiry_date]': item['expiry_date'],
      if (item['issued_date'] != null)
        'document[issued_date]': item['issued_date'],
      if (item['number'] != null) 'document[number]': item['number'],
      'document[file]': multipart,
    });
    await _dio.post(Endpoints.meDocuments, data: form);
  }

  Future<List<DriverNotification>> fetchActivityTimeline() async {
    final all = await _notificationsRepository.fetchNotifications();
    const allowed = {
      'driver.score_published',
      'driver.tier_changed',
      'driver.badge_earned',
      'compliance.driver_document_expiring',
      'compliance.driver_document_expired',
      'compliance.driver_document_uploaded',
      'compliance.driver_document_verified',
      'compliance.driver_document_rejected',
      'vehicle.insurance_status_changed',
    };
    return all.where((n) {
      final t = (n.notificationType ?? '').toLowerCase();
      return allowed.contains(t);
    }).toList();
  }

  Future<String?> currentRole() async {
    try {
      final token = await _tokenStorage.readToken();
      if (token == null || token.isEmpty) return null;
      final parts = token.split('.');
      if (parts.length < 2) return null;
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final map = jsonDecode(payload) as Map<String, dynamic>;
      final role = map['role']?.toString().toLowerCase();
      if (role != null && role.isNotEmpty) return role;
      final scope = map['scp']?.toString().toLowerCase();
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

  Future<DriverProfileData?> _fallbackProfileFromToken() async {
    try {
      final token = await _tokenStorage.readToken();
      if (token == null || token.isEmpty) return null;
      final parts = token.split('.');
      if (parts.length < 2) return null;
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final claims = jsonDecode(payload) as Map<String, dynamic>;
      final driverId = int.tryParse(claims['sub']?.toString() ?? '') ?? 0;

      int? vehicleId;
      String name = 'Driver #$driverId';
      try {
        final tripsRes = await _dio.get(Endpoints.trips);
        final trips = _pickList(tripsRes.data);
        if (trips.isNotEmpty) {
          final first = trips.first;
          final vehicle = first['vehicle'];
          if (vehicle is Map) {
            final v = vehicle['id'];
            if (v is int) vehicleId = v;
            if (v is num) vehicleId = v.toInt();
            if (v is String) vehicleId = int.tryParse(v);
          }
          final driver = first['driver'];
          if (driver is Map &&
              (driver['name']?.toString().isNotEmpty ?? false)) {
            name = driver['name'].toString();
          } else if ((first['driver_name']?.toString().isNotEmpty ?? false)) {
            name = first['driver_name'].toString();
          }
        }
      } catch (_) {}

      return DriverProfileData(
        driverId: driverId,
        name: name,
        tier: 'bronze',
        overallScore: 0,
        trend: 'stable',
        vehicleId: vehicleId,
        dimensions: const {
          'safety': 0,
          'efficiency': 0,
          'compliance': 0,
          'timeliness': 0,
          'professionalism': 0,
        },
      );
    } catch (_) {
      return null;
    }
  }

  Future<DriverHubLoad<T>> _fetchAndCache<T>({
    required String key,
    required Future<Response<dynamic>> Function() request,
    required T Function(dynamic data) parser,
  }) async {
    final syncKey = 'sync_at_$key';
    try {
      final response = await request();
      final parsed = parser(response.data);
      await _cache.put(key, {
        'payload': _encode(parsed),
        'stored_at': DateTime.now().toIso8601String(),
      });
      return DriverHubLoad(
        data: parsed,
        fromCache: false,
        lastSyncAt: DateTime.now(),
      );
    } catch (_) {
      final cached = _cache.get(key);
      if (cached != null) {
        final payload = cached['payload'];
        final storedAt = DateTime.tryParse(
          (cached['stored_at'] ?? '').toString(),
        )?.toLocal();
        return DriverHubLoad(
          data: _decode<T>(payload),
          fromCache: true,
          lastSyncAt:
              storedAt ?? DateTime.tryParse((cached[syncKey] ?? '').toString()),
        );
      }
      rethrow;
    }
  }

  dynamic _encode(dynamic parsed) {
    if (parsed is DriverProfileData) return parsed.toJson();
    if (parsed is DriverRank) return parsed.toJson();
    if (parsed is VehicleInsuranceBlock) return parsed.toJson();
    if (parsed is List<DriverBadge>) {
      return parsed.map((e) => e.toJson()).toList();
    }
    if (parsed is List<ImprovementTip>) {
      return parsed.map((e) => e.toJson()).toList();
    }
    if (parsed is List<DriverDocumentItem>) {
      return parsed.map((e) => e.toJson()).toList();
    }
    if (parsed is List<DriverScorePoint>) {
      return parsed
          .map(
            (e) => {
              'label': e.label,
              'overall': e.overall,
              'dimensions': e.dimensions,
            },
          )
          .toList();
    }
    return parsed;
  }

  T _decode<T>(dynamic payload) {
    if (T == DriverProfileData) {
      return DriverProfileData.fromJson(_pickMap(payload)) as T;
    }
    if (T == DriverRank) return DriverRank.fromJson(_pickMap(payload)) as T;
    if (T == VehicleInsuranceBlock ||
        T.toString() == 'VehicleInsuranceBlock?') {
      if (payload == null) return null as T;
      return VehicleInsuranceBlock.fromJson(_pickMap(payload)) as T;
    }
    if (T == List<DriverBadge>) {
      return _pickList(payload).map(DriverBadge.fromJson).toList() as T;
    }
    if (T == List<ImprovementTip>) {
      return _pickList(payload).map(ImprovementTip.fromJson).toList() as T;
    }
    if (T == List<DriverDocumentItem>) {
      return _pickList(payload).map(DriverDocumentItem.fromJson).toList() as T;
    }
    if (T == List<DriverScorePoint>) {
      return _pickList(payload)
              .map(
                (e) => DriverScorePoint(
                  label: (e['label'] ?? 'Period').toString(),
                  overall: _toDouble(e['overall']),
                  dimensions: (e['dimensions'] is Map)
                      ? Map<String, dynamic>.from(
                          e['dimensions'] as Map,
                        ).map((k, v) => MapEntry(k, _toDouble(v)))
                      : const <String, double>{},
                ),
              )
              .toList()
          as T;
    }
    throw Exception('Unsupported decode type: $T');
  }

  Map<String, dynamic> _pickMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _pickList(dynamic raw) {
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (raw is Map) {
      for (final key in [
        'data',
        'items',
        'scores',
        'badges',
        'tips',
        'documents',
      ]) {
        final v = raw[key];
        if (v is List) {
          return v
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }
    }
    return const <Map<String, dynamic>>[];
  }

  double _toDouble(dynamic v, {double fallback = 0}) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }
}

final driverHubRepositoryProvider = Provider<DriverHubRepository>((ref) {
  final dio = ref.read(dioProvider);
  final cache = Hive.box<Map>(HiveBoxes.driverHubCache);
  final docQueue = Hive.box<Map>(HiveBoxes.driverDocumentsUploadQueue);
  final tokenStorage = ref.read(tokenStorageProvider);
  final tripsRepo = ref.read(tripsRepositoryProvider);
  final notificationsRepo = ref.read(notificationsRepositoryProvider);
  return DriverHubRepository(
    dio,
    cache,
    docQueue,
    tokenStorage,
    tripsRepo,
    notificationsRepo,
  );
});
