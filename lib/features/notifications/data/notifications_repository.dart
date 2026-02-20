import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';

class DriverNotification {
  DriverNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.read,
    required this.archived,
    this.notificationType,
    this.actionType,
    this.actionUrl,
    this.data = const <String, dynamic>{},
  });

  final int id;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool read;
  final bool archived;
  final String? notificationType;
  final String? actionType;
  final String? actionUrl;
  final Map<String, dynamic> data;

  DriverNotification copyWith({bool? read, bool? archived}) {
    return DriverNotification(
      id: id,
      title: title,
      body: body,
      createdAt: createdAt,
      read: read ?? this.read,
      archived: archived ?? this.archived,
      notificationType: notificationType,
      actionType: actionType,
      actionUrl: actionUrl,
      data: data,
    );
  }

  factory DriverNotification.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    bool toBool(dynamic value) {
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        final v = value.toLowerCase().trim();
        return v == 'true' || v == '1' || v == 'yes';
      }
      return false;
    }

    DateTime? toDate(dynamic value) {
      if (value is String) return DateTime.tryParse(value)?.toLocal();
      return null;
    }

    Map<String, dynamic> toMap(dynamic value) {
      if (value is Map<String, dynamic>) return value;
      if (value is Map) return Map<String, dynamic>.from(value);
      return const <String, dynamic>{};
    }

    return DriverNotification(
      id: toInt(json['id']),
      title: (json['title'] ?? json['subject'] ?? 'Notification').toString(),
      body: (json['body'] ?? json['message'] ?? '').toString(),
      createdAt:
          toDate(json['created_at'] ?? json['sent_at'] ?? json['timestamp']) ??
          DateTime.now(),
      read: toBool(json['read'] ?? json['is_read'] ?? json['read_at'] != null),
      archived: toBool(json['archived'] ?? json['is_archived']),
      notificationType: json['notification_type']?.toString(),
      actionType: json['action_type']?.toString(),
      actionUrl: json['action_url']?.toString(),
      data: toMap(json['data']),
    );
  }
}

class NotificationPreferences {
  NotificationPreferences({
    required this.typeEnabled,
    this.quietHoursStart,
    this.quietHoursEnd,
  });

  final Map<String, bool> typeEnabled;
  final String? quietHoursStart;
  final String? quietHoursEnd;

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    Map<String, bool> parseTypes(dynamic value) {
      if (value is Map) {
        return value.map((key, dynamic v) {
          final enabled = (v is bool)
              ? v
              : (v is num)
              ? v != 0
              : v.toString().toLowerCase() == 'true';
          return MapEntry(key.toString(), enabled);
        });
      }
      if (value is List) {
        final map = <String, bool>{};
        for (final item in value) {
          if (item is Map) {
            final type = (item['type'] ?? item['name'] ?? '').toString();
            if (type.isEmpty) continue;
            final enabled = item['enabled'] == true || item['active'] == true;
            map[type] = enabled;
          }
        }
        return map;
      }
      return const <String, bool>{};
    }

    final quiet = (json['quiet_hours'] is Map)
        ? Map<String, dynamic>.from(json['quiet_hours'] as Map)
        : const <String, dynamic>{};

    return NotificationPreferences(
      typeEnabled: parseTypes(
        json['types'] ?? json['preferences'] ?? json['notification_types'],
      ),
      quietHoursStart: (quiet['start'] ?? json['quiet_hours_start'])
          ?.toString(),
      quietHoursEnd: (quiet['end'] ?? json['quiet_hours_end'])?.toString(),
    );
  }

  Map<String, dynamic> toApiPayload() {
    return {
      'preferences': {
        'types': typeEnabled,
        'quiet_hours': {
          if (quietHoursStart != null) 'start': quietHoursStart,
          if (quietHoursEnd != null) 'end': quietHoursEnd,
        },
      },
    };
  }
}

class NotificationsRepository {
  NotificationsRepository(this._dio);
  final Dio _dio;
  static const _prefsEndpointUnavailableKey =
      'notifications_prefs_endpoint_unavailable';

  List<Map<String, dynamic>> _pickList(dynamic raw) {
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (raw is Map) {
      for (final key in ['data', 'items', 'notifications']) {
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

  Map<String, dynamic> _pickMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const <String, dynamic>{};
  }

  Future<bool> _isPrefsEndpointUnavailable() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsEndpointUnavailableKey) ?? false;
  }

  Future<void> _setPrefsEndpointUnavailable(bool unavailable) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsEndpointUnavailableKey, unavailable);
  }

  Future<List<DriverNotification>> fetchNotifications() async {
    final response = await _dio.get(Endpoints.notifications);
    final list = _pickList(response.data);
    final notifications = list.map(DriverNotification.fromJson).toList();
    notifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return notifications;
  }

  Future<int> fetchUnreadCount() async {
    final response = await _dio.get(Endpoints.notificationsUnreadCount);
    final map = _pickMap(response.data);
    final value = map['count'] ?? map['unread_count'] ?? map['unread'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  Future<void> markAsRead(int id) async {
    try {
      await _dio.patch(Endpoints.notificationMarkRead(id));
    } on DioException catch (e) {
      if (e.response?.statusCode == 404 || e.response?.statusCode == 405) {
        await _dio.patch(
          Endpoints.notificationById(id),
          data: {
            'notification': {'read': true},
          },
        );
        return;
      }
      rethrow;
    }
  }

  Future<void> archive(int id) async {
    try {
      await _dio.patch(Endpoints.notificationArchive(id));
    } on DioException catch (e) {
      if (e.response?.statusCode == 404 || e.response?.statusCode == 405) {
        await _dio.patch(
          Endpoints.notificationById(id),
          data: {
            'notification': {'archived': true},
          },
        );
        return;
      }
      rethrow;
    }
  }

  Future<void> delete(int id) async {
    await _dio.delete(Endpoints.notificationById(id));
  }

  Future<NotificationPreferences> fetchPreferences() async {
    if (await _isPrefsEndpointUnavailable()) {
      return NotificationPreferences(typeEnabled: const <String, bool>{});
    }
    try {
      final response = await _dio.get(Endpoints.notificationPreferences);
      final root = _pickMap(response.data);
      final map = _pickMap(root['preferences'] ?? root['data'] ?? root);
      await _setPrefsEndpointUnavailable(false);
      return NotificationPreferences.fromJson(map);
    } on DioException catch (e) {
      final code = e.response?.statusCode ?? 0;
      if (code == 404 || code == 405 || code == 501) {
        await _setPrefsEndpointUnavailable(true);
        return NotificationPreferences(typeEnabled: const <String, bool>{});
      }
      rethrow;
    }
  }

  Future<void> updatePreferences(NotificationPreferences preferences) async {
    if (await _isPrefsEndpointUnavailable()) return;
    try {
      await _dio.patch(
        Endpoints.notificationPreferences,
        data: preferences.toApiPayload(),
      );
      await _setPrefsEndpointUnavailable(false);
    } on DioException catch (e) {
      final code = e.response?.statusCode ?? 0;
      if (code == 404 || code == 405 || code == 501) {
        await _setPrefsEndpointUnavailable(true);
        return;
      }
      rethrow;
    }
  }
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>((
  ref,
) {
  final dio = ref.read(dioProvider);
  return NotificationsRepository(dio);
});

final notificationsUnreadCountProvider = FutureProvider<int>((ref) async {
  return ref.read(notificationsRepositoryProvider).fetchUnreadCount();
});
