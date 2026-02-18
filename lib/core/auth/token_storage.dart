import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  TokenStorage(this._storage);

  static const _key = 'auth_token';
  final FlutterSecureStorage _storage;
  String? _cachedToken;

  Future<String?> readToken() async {
    if (_cachedToken != null && _cachedToken!.isNotEmpty) {
      return _cachedToken;
    }
    final token = await _storage.read(key: _key);
    if (token != null && token.isNotEmpty) {
      _cachedToken = token;
    }
    return token;
  }

  Future<void> writeToken(String token) async {
    _cachedToken = token;
    await _storage.write(key: _key, value: token);
  }

  Future<void> clearToken() async {
    _cachedToken = null;
    await _storage.delete(key: _key);
  }
}

final tokenStorageProvider = Provider<TokenStorage>((ref) {
  return TokenStorage(const FlutterSecureStorage());
});
