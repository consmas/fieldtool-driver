import 'package:dio/dio.dart';

import '../api/endpoints.dart';
import '../errors/app_error.dart';

class AuthService {
  AuthService(this._dio);

  final Dio _dio;

  Future<String> login(String email, String password) async {
    try {
      final response = await _dio.post(Endpoints.login, data: {
        'user': {
          'email': email,
          'password': password,
        },
      });
      final headers = response.headers.map.map((key, value) => MapEntry(key, value.join(',')));
      // Debug logging for auth headers
      // ignore: avoid_print
      print('AuthService.login headers: $headers');
      final authHeader =
          response.headers.value('authorization') ?? response.headers.value('Authorization');
      // ignore: avoid_print
      print('AuthService.login authHeader: $authHeader');
      final token = authHeader?.replaceFirst('Bearer ', '').trim();
      if (token == null || token.isEmpty) {
        throw AppError('Invalid login response.');
      }
      return token;
    } on DioException catch (e) {
      // Debug response details for login failures
      // ignore: avoid_print
      print('AuthService.login error status: ${e.response?.statusCode}');
      // ignore: avoid_print
      print('AuthService.login error data: ${e.response?.data}');
      final message = e.response?.data is Map
          ? (e.response?.data['error']?.toString() ?? 'Login failed.')
          : 'Login failed.';
      throw AppError(message);
    }
  }

  Future<void> logout() async {
    await _dio.delete(Endpoints.logout);
  }
}
