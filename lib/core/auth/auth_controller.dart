import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import 'auth_service.dart';
import 'auth_state.dart';
import 'token_storage.dart';

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._storage, this._service) : super(const AuthState.unknown()) {
    _load();
  }

  final TokenStorage _storage;
  final AuthService _service;

  Future<void> _load() async {
    final token = await _storage.readToken();
    if (token != null && token.isNotEmpty) {
      state = AuthState.authenticated(token);
    } else {
      state = const AuthState.unauthenticated();
    }
  }

  Future<void> login(String email, String password) async {
    state = const AuthState(status: AuthStatus.unknown);
    try {
      final token = await _service.login(email, password);
      await _storage.writeToken(token);
      state = AuthState.authenticated(token);
    } catch (e) {
      state = AuthState.unauthenticated(e.toString());
    }
  }

  Future<void> logout() async {
    try {
      await _service.logout();
    } catch (_) {}
    await _storage.clearToken();
    state = const AuthState.unauthenticated();
  }

  Future<void> forceLogout() async {
    await _storage.clearToken();
    state = const AuthState.unauthenticated();
  }
}

final authServiceProvider = Provider<AuthService>((ref) {
  final dio = ref.read(dioProvider);
  return AuthService(dio);
});

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
  final storage = ref.read(tokenStorageProvider);
  final service = ref.read(authServiceProvider);
  return AuthController(storage, service);
});
