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
///
/// **Remember Me logic:**
/// If `persist` is false in [saveTokens], the refresh token is stored only
/// in memory (never written to secure storage). On next launch, no refresh
/// token is found → session restore fails → user lands on login screen.
class TokenStorage {
  const TokenStorage(this._storage);

  final FlutterSecureStorage _storage;

  /// In-memory refresh token — used when rememberMe is false.
  static String? _memoryRefreshToken;

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    bool persist = true,
  }) async {
    await _storage.write(key: _Keys.accessToken, value: accessToken);
    if (persist) {
      await _storage.write(key: _Keys.refreshToken, value: refreshToken);
      _memoryRefreshToken = null; // clear memory if previously set
    } else {
      // Keep refresh token only in memory; delete any previously persisted one.
      await _storage.delete(key: _Keys.refreshToken);
      _memoryRefreshToken = refreshToken;
    }
  }

  Future<String?> getAccessToken() => _storage.read(key: _Keys.accessToken);

  Future<String?> getRefreshToken() async {
    final stored = await _storage.read(key: _Keys.refreshToken);
    return stored ?? _memoryRefreshToken;
  }

  Future<void> clearTokens() async {
    _memoryRefreshToken = null;
    await Future.wait([
      _storage.delete(key: _Keys.accessToken),
      _storage.delete(key: _Keys.refreshToken),
    ]);
  }
}
