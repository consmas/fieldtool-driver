import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';

class DeviceRegistrationService {
  DeviceRegistrationService(this._dio);
  final Dio _dio;

  static const _prefDeviceToken = 'driver_device_registration_token';
  static const _prefRegistered = 'driver_device_registered_once';

  Future<String> getOrCreateDeviceToken() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_prefDeviceToken);
    if (existing != null && existing.isNotEmpty) return existing;
    final token = const Uuid().v4();
    await prefs.setString(_prefDeviceToken, token);
    return token;
  }

  Future<void> registerDevice() async {
    final token = await getOrCreateDeviceToken();
    final prefs = await SharedPreferences.getInstance();
    try {
      await _dio.post(
        Endpoints.devices,
        data: {
          'device': {
            'token': token,
            'platform': Platform.operatingSystem,
            'app': 'consmas_fieldtool_driver',
          },
        },
      );
      await prefs.setBool(_prefRegistered, true);
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        await prefs.setBool(_prefRegistered, true);
        return;
      }
      rethrow;
    }
  }

  Future<void> unregisterDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_prefDeviceToken);
    if (token == null || token.isEmpty) return;
    try {
      await _dio.delete(Endpoints.deviceByToken(Uri.encodeComponent(token)));
    } on DioException catch (e) {
      if (e.response?.statusCode == 404 || e.response?.statusCode == 405) {
        await _dio.delete(
          Endpoints.devices,
          data: {
            'device': {'token': token},
          },
        );
      } else {
        rethrow;
      }
    } finally {
      await prefs.remove(_prefRegistered);
    }
  }
}

final deviceRegistrationServiceProvider = Provider<DeviceRegistrationService>((
  ref,
) {
  final dio = ref.read(dioProvider);
  return DeviceRegistrationService(dio);
});
