import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keys used in flutter_secure_storage.
/// Never store tokens in SharedPreferences — use this class only.
abstract final class _Keys {
  static const accessToken = 'tn_access_token';
  static const refreshToken = 'tn_refresh_token';
}

/// Wraps [FlutterSecureStorage] for JWT access and refresh token persistence.
///
/// - Uses iOS Keychain on iOS and Android Keystore on Android.
/// - Tokens are ONLY accessed here and in [AuthInterceptor].
/// - Feature-level code must never call this class directly.
class TokenStorage {
  const TokenStorage(this._storage);

  final FlutterSecureStorage _storage;

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      _storage.write(key: _Keys.accessToken, value: accessToken),
      _storage.write(key: _Keys.refreshToken, value: refreshToken),
    ]);
  }

  Future<String?> getAccessToken() => _storage.read(key: _Keys.accessToken);

  Future<String?> getRefreshToken() => _storage.read(key: _Keys.refreshToken);

  Future<void> clearTokens() async {
    await Future.wait([
      _storage.delete(key: _Keys.accessToken),
      _storage.delete(key: _Keys.refreshToken),
    ]);
  }
}
