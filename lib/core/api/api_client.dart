import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/env.dart';
import '../auth/token_storage.dart';
import '../utils/logger.dart';

final dioProvider = Provider<Dio>((ref) {
  final storage = ref.read(tokenStorageProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: Env.apiBaseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Accept': 'application/json',
      },
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await storage.readToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        Logger.d(
          'HTTP ${options.method} ${options.baseUrl}${options.path} '
          'headers=${options.headers} '
          'data=${options.data}',
        );
        return handler.next(options);
      },
      onResponse: (response, handler) {
        Logger.d(
          'HTTP ${response.statusCode} ${response.requestOptions.method} '
          '${response.requestOptions.baseUrl}${response.requestOptions.path} '
          'data=${response.data}',
        );
        return handler.next(response);
      },
      onError: (error, handler) {
        Logger.e(
          'HTTP ERROR ${error.requestOptions.method} '
          '${error.requestOptions.baseUrl}${error.requestOptions.path} '
          'status=${error.response?.statusCode} '
          'data=${error.response?.data}',
          error,
        );
        return handler.next(error);
      },
    ),
  );

  return dio;
});
