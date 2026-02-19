import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/token_storage.dart';
import '../../offline/hive_boxes.dart';

class MaintenanceRepositoryException implements Exception {
  MaintenanceRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
}

class MaintenanceVehicleStatus {
  MaintenanceVehicleStatus({
    this.nextDueMaintenance,
    this.isOverdue = false,
    this.isDueSoon = false,
    this.daysToDue,
    this.kmToDue,
    this.currentOdometerKm,
    this.nextServiceLabel,
  });

  final DateTime? nextDueMaintenance;
  final bool isOverdue;
  final bool isDueSoon;
  final int? daysToDue;
  final double? kmToDue;
  final double? currentOdometerKm;
  final String? nextServiceLabel;

  Map<String, dynamic> toJson() => {
    'next_due_maintenance': nextDueMaintenance?.toIso8601String(),
    'is_overdue': isOverdue,
    'is_due_soon': isDueSoon,
    'days_to_due': daysToDue,
    'km_to_due': kmToDue,
    'current_odometer_km': currentOdometerKm,
    'next_service_label': nextServiceLabel,
  };

  factory MaintenanceVehicleStatus.fromJson(Map<String, dynamic> json) {
    DateTime? toDate(dynamic value) {
      if (value is String) return DateTime.tryParse(value)?.toLocal();
      return null;
    }

    double? toDouble(dynamic value) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value);
      return null;
    }

    int? toInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value);
      return null;
    }

    bool toBool(dynamic value) {
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        final v = value.trim().toLowerCase();
        return v == 'true' || v == '1' || v == 'yes';
      }
      return false;
    }

    return MaintenanceVehicleStatus(
      nextDueMaintenance: toDate(
        json['next_due_maintenance'] ??
            json['next_due_date'] ??
            json['due_at'] ??
            json['maintenance_due_at'],
      ),
      isOverdue: toBool(
        json['is_overdue'] ?? json['overdue'] ?? json['maintenance_overdue'],
      ),
      isDueSoon: toBool(json['is_due_soon'] ?? json['due_soon']),
      daysToDue: toInt(json['days_to_due'] ?? json['due_in_days']),
      kmToDue: toDouble(json['km_to_due'] ?? json['due_in_km']),
      currentOdometerKm: toDouble(
        json['current_odometer_km'] ?? json['odometer_km'],
      ),
      nextServiceLabel:
          (json['next_service_label'] ??
                  json['next_due_title'] ??
                  json['maintenance_type'])
              ?.toString(),
    );
  }
}

enum VehicleDocumentStatus { active, expiring, expired, unknown }

class VehicleDocument {
  VehicleDocument({
    required this.id,
    required this.type,
    this.expiryDate,
    required this.status,
    this.number,
  });

  final int id;
  final String type;
  final DateTime? expiryDate;
  final VehicleDocumentStatus status;
  final String? number;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'expiry_date': expiryDate?.toIso8601String(),
    'status': status.name,
    'number': number,
  };

  factory VehicleDocument.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    DateTime? toDate(dynamic value) {
      if (value is String) return DateTime.tryParse(value)?.toLocal();
      return null;
    }

    VehicleDocumentStatus mapStatus(dynamic value) {
      final v = (value ?? '').toString().toLowerCase();
      if (v == 'active' || v == 'valid') return VehicleDocumentStatus.active;
      if (v == 'expiring' || v == 'due_soon') {
        return VehicleDocumentStatus.expiring;
      }
      if (v == 'expired') return VehicleDocumentStatus.expired;
      return VehicleDocumentStatus.unknown;
    }

    return VehicleDocument(
      id: toInt(json['id'] ?? json['document_id']),
      type:
          (json['type'] ?? json['document_type'] ?? json['name'] ?? 'Document')
              .toString(),
      expiryDate: toDate(json['expiry_date'] ?? json['expires_at']),
      status: mapStatus(json['status']),
      number: json['number']?.toString(),
    );
  }
}

class WorkOrder {
  WorkOrder({
    required this.id,
    required this.number,
    required this.title,
    required this.status,
    this.scheduledDate,
    this.notes,
    this.canComment = false,
  });

  final int id;
  final String number;
  final String title;
  final String status;
  final DateTime? scheduledDate;
  final String? notes;
  final bool canComment;

  Map<String, dynamic> toJson() => {
    'id': id,
    'number': number,
    'title': title,
    'status': status,
    'scheduled_date': scheduledDate?.toIso8601String(),
    'notes': notes,
    'can_comment': canComment,
  };

  factory WorkOrder.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    DateTime? toDate(dynamic value) {
      if (value is String) return DateTime.tryParse(value)?.toLocal();
      return null;
    }

    bool toBool(dynamic value) {
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        final v = value.trim().toLowerCase();
        return v == 'true' || v == '1' || v == 'yes';
      }
      return false;
    }

    return WorkOrder(
      id: toInt(json['id'] ?? json['work_order_id']),
      number: (json['number'] ?? json['wo_number'] ?? 'WO-${json['id'] ?? 0}')
          .toString(),
      title: (json['title'] ?? json['summary'] ?? 'Work Order').toString(),
      status: (json['status'] ?? 'pending').toString(),
      scheduledDate: toDate(
        json['scheduled_date'] ?? json['scheduled_at'] ?? json['eta'],
      ),
      notes: json['notes']?.toString(),
      canComment: toBool(json['can_comment']),
    );
  }
}

class MaintenanceAlert {
  MaintenanceAlert({required this.type, required this.message, this.createdAt});

  final String type;
  final String message;
  final DateTime? createdAt;

  Map<String, dynamic> toJson() => {
    'type': type,
    'message': message,
    'created_at': createdAt?.toIso8601String(),
  };

  factory MaintenanceAlert.fromJson(Map<String, dynamic> json) {
    return MaintenanceAlert(
      type: (json['type'] ?? json['event_type'] ?? '').toString(),
      message: (json['message'] ?? json['body'] ?? '').toString(),
      createdAt: DateTime.tryParse(
        (json['created_at'] ?? json['timestamp'] ?? '').toString(),
      )?.toLocal(),
    );
  }
}

class MaintenanceSnapshot {
  MaintenanceSnapshot({
    required this.status,
    required this.documents,
    required this.workOrders,
    required this.alerts,
    required this.fetchedAt,
    required this.allowWorkOrderComments,
  });

  final MaintenanceVehicleStatus status;
  final List<VehicleDocument> documents;
  final List<WorkOrder> workOrders;
  final List<MaintenanceAlert> alerts;
  final DateTime fetchedAt;
  final bool allowWorkOrderComments;

  Map<String, dynamic> toJson() => {
    'status': status.toJson(),
    'documents': documents.map((e) => e.toJson()).toList(),
    'work_orders': workOrders.map((e) => e.toJson()).toList(),
    'alerts': alerts.map((e) => e.toJson()).toList(),
    'fetched_at': fetchedAt.toIso8601String(),
    'allow_work_order_comments': allowWorkOrderComments,
  };

  factory MaintenanceSnapshot.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> toMapList(dynamic value) {
      if (value is List) {
        return value
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return const <Map<String, dynamic>>[];
    }

    return MaintenanceSnapshot(
      status: MaintenanceVehicleStatus.fromJson(
        Map<String, dynamic>.from((json['status'] ?? {}) as Map),
      ),
      documents: toMapList(
        json['documents'],
      ).map(VehicleDocument.fromJson).toList(),
      workOrders: toMapList(
        json['work_orders'],
      ).map(WorkOrder.fromJson).toList(),
      alerts: toMapList(json['alerts']).map(MaintenanceAlert.fromJson).toList(),
      fetchedAt:
          DateTime.tryParse(json['fetched_at']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
      allowWorkOrderComments: (json['allow_work_order_comments'] == true),
    );
  }
}

class MaintenanceSnapshotResult {
  MaintenanceSnapshotResult({
    required this.snapshot,
    required this.fromCache,
    this.warning,
  });

  final MaintenanceSnapshot snapshot;
  final bool fromCache;
  final String? warning;
}

class MaintenanceRepository {
  MaintenanceRepository(this._dio, this._tokenStorage, this._cacheBox);

  final Dio _dio;
  final TokenStorage _tokenStorage;
  final Box<Map> _cacheBox;

  static const _cacheKey = 'maintenance_snapshot_v1';
  static const _supportedAlertTypes = <String>{
    'maintenance.due_soon',
    'maintenance.overdue',
    'maintenance.work_order_created',
    'maintenance.work_order_completed',
  };

  Future<Response<dynamic>> _getFromCandidates(List<String> candidates) async {
    DioException? lastError;
    for (final path in candidates) {
      try {
        return await _dio.get(path);
      } on DioException catch (e) {
        lastError = e;
        if (e.response?.statusCode == 404) continue;
        rethrow;
      }
    }
    throw lastError ??
        DioException(
          requestOptions: RequestOptions(path: candidates.join(', ')),
          message: 'No maintenance endpoint available.',
        );
  }

  Future<MaintenanceSnapshotResult> fetchSnapshot() async {
    try {
      final role = await _currentRole();

      final combinedResponse = await _getFromCandidates([
        '/maintenance/my_vehicle',
        '/maintenance/snapshot',
        '/drivers/me/maintenance',
      ]);
      final combinedMap = _pickMap(combinedResponse.data);
      if (combinedMap.isNotEmpty &&
          (combinedMap['status'] != null ||
              combinedMap['documents'] != null ||
              combinedMap['work_orders'] != null)) {
        final snapshot = _parseSnapshotFromCombined(combinedMap, role);
        await _writeCache(snapshot);
        return MaintenanceSnapshotResult(snapshot: snapshot, fromCache: false);
      }

      final statusResponse = await _getFromCandidates([
        '/maintenance/my_vehicle/status',
        '/maintenance/vehicle/status',
        '/drivers/me/vehicle/status',
      ]);
      final docsResponse = await _getFromCandidates([
        '/maintenance/my_vehicle/documents',
        '/maintenance/vehicle/documents',
        '/drivers/me/vehicle/documents',
      ]);
      final woResponse = await _getFromCandidates([
        '/maintenance/my_vehicle/work_orders',
        '/maintenance/work_orders/my_vehicle',
        '/drivers/me/vehicle/work_orders',
      ]);
      final alertsResponse = await _getFromCandidates([
        '/maintenance/alerts',
        '/alerts/maintenance',
      ]);

      final status = MaintenanceVehicleStatus.fromJson(
        _pickMap(statusResponse.data['status'] ?? statusResponse.data),
      );
      final documents = _pickList(
        docsResponse.data['documents'] ?? docsResponse.data,
      ).map(VehicleDocument.fromJson).toList();
      final workOrders = _pickList(
        woResponse.data['work_orders'] ?? woResponse.data,
      ).map(WorkOrder.fromJson).toList();
      final alerts = _pickList(
        alertsResponse.data['alerts'] ?? alertsResponse.data,
      ).map(MaintenanceAlert.fromJson).where(_isSupportedAlert).toList();

      final snapshot = MaintenanceSnapshot(
        status: status,
        documents: documents,
        workOrders: workOrders,
        alerts: alerts,
        fetchedAt: DateTime.now(),
        allowWorkOrderComments: _roleAllowsComments(role),
      );
      await _writeCache(snapshot);
      return MaintenanceSnapshotResult(snapshot: snapshot, fromCache: false);
    } on DioException catch (e) {
      final cached = _readCache();
      if (cached != null) {
        return MaintenanceSnapshotResult(
          snapshot: cached,
          fromCache: true,
          warning:
              'Showing cached maintenance data. Network error: ${e.message ?? 'request failed'}',
        );
      }
      throw MaintenanceRepositoryException(
        'Could not load maintenance data. Check your network and try again.',
      );
    } catch (e) {
      final cached = _readCache();
      if (cached != null) {
        return MaintenanceSnapshotResult(
          snapshot: cached,
          fromCache: true,
          warning: 'Showing cached maintenance data.',
        );
      }
      throw MaintenanceRepositoryException(
        'Could not load maintenance data: $e',
      );
    }
  }

  Future<MaintenanceVehicleStatus> fetchVehicleStatusOnly() async {
    final result = await fetchSnapshot();
    return result.snapshot.status;
  }

  Future<void> addWorkOrderComment({
    required int workOrderId,
    required String comment,
  }) async {
    final body = comment.trim();
    if (body.isEmpty) {
      throw MaintenanceRepositoryException('Comment cannot be empty.');
    }
    DioException? lastError;
    for (final path in [
      '/maintenance/work_orders/$workOrderId/comments',
      '/work_orders/$workOrderId/comments',
    ]) {
      try {
        await _dio.post(
          path,
          data: {
            'comment': {'body': body},
          },
        );
        return;
      } on DioException catch (e) {
        lastError = e;
        if (e.response?.statusCode == 404) continue;
        rethrow;
      }
    }
    throw MaintenanceRepositoryException(
      'Could not add work order comment. ${lastError?.message ?? ''}'.trim(),
    );
  }

  bool _isSupportedAlert(MaintenanceAlert alert) {
    return _supportedAlertTypes.contains(alert.type);
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
      final candidates = [
        raw['data'],
        raw['items'],
        raw['documents'],
        raw['work_orders'],
        raw['alerts'],
      ];
      for (final candidate in candidates) {
        if (candidate is List) {
          return candidate
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }
    }
    return const <Map<String, dynamic>>[];
  }

  MaintenanceSnapshot _parseSnapshotFromCombined(
    Map<String, dynamic> map,
    String? role,
  ) {
    final status = MaintenanceVehicleStatus.fromJson(
      _pickMap(map['status'] ?? map['vehicle_status']),
    );
    final documents = _pickList(
      map['documents'],
    ).map(VehicleDocument.fromJson).toList();
    final workOrders = _pickList(
      map['work_orders'],
    ).map(WorkOrder.fromJson).toList();
    final alerts = _pickList(
      map['alerts'],
    ).map(MaintenanceAlert.fromJson).where(_isSupportedAlert).toList();
    final allowComments =
        map['allow_work_order_comments'] == true || _roleAllowsComments(role);
    return MaintenanceSnapshot(
      status: status,
      documents: documents,
      workOrders: workOrders,
      alerts: alerts,
      fetchedAt: DateTime.now(),
      allowWorkOrderComments: allowComments,
    );
  }

  bool _roleAllowsComments(String? role) {
    final normalized = (role ?? '').toLowerCase();
    return normalized == 'admin' ||
        normalized == 'supervisor' ||
        normalized == 'dispatcher' ||
        normalized == 'maintenance' ||
        normalized == 'maintenance_manager';
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
      final map = jsonDecode(payload) as Map<String, dynamic>;
      return map['role']?.toString();
    } catch (_) {
      return null;
    }
  }

  MaintenanceSnapshot? _readCache() {
    final map = _cacheBox.get(_cacheKey);
    if (map == null || map.isEmpty) return null;
    return MaintenanceSnapshot.fromJson(Map<String, dynamic>.from(map));
  }

  Future<void> _writeCache(MaintenanceSnapshot snapshot) async {
    await _cacheBox.put(_cacheKey, snapshot.toJson());
  }
}

final maintenanceRepositoryProvider = Provider<MaintenanceRepository>((ref) {
  final dio = ref.read(dioProvider);
  final tokenStorage = ref.read(tokenStorageProvider);
  final box = Hive.box<Map>(HiveBoxes.maintenanceSnapshotCache);
  return MaintenanceRepository(dio, tokenStorage, box);
});
