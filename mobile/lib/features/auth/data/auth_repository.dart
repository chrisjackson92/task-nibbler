import 'package:dio/dio.dart';

import '../../../core/api/models/api_error.dart';
import '../../../core/api/models/auth_models.dart';
import '../../../core/auth/token_storage.dart';

/// Repository wrapping the auth API routes (CON-002 §1).
/// Always returns typed models — never raw [Response] or [dynamic].
class AuthRepository {
  const AuthRepository({
    required this.dio,
    required this.tokenStorage,
  });

  final Dio dio;
  final TokenStorage tokenStorage;

  // ── Register ──────────────────────────────────────────────────────────────

  Future<AuthResponse> register(RegisterRequest request) async {
    final response = await dio.post<Map<String, dynamic>>(
      '/api/v1/auth/register',
      data: request.toJson(),
    );
    final auth = AuthResponse.fromJson(response.data!);
    await tokenStorage.saveTokens(
      accessToken: auth.accessToken,
      refreshToken: auth.refreshToken,
    );
    return auth;
  }

  // ── Login ─────────────────────────────────────────────────────────────────

  Future<AuthResponse> login(LoginRequest request) async {
    final response = await dio.post<Map<String, dynamic>>(
      '/api/v1/auth/login',
      data: request.toJson(),
    );
    final auth = AuthResponse.fromJson(response.data!);
    await tokenStorage.saveTokens(
      accessToken: auth.accessToken,
      refreshToken: auth.refreshToken,
    );
    return auth;
  }

  // ── Logout ────────────────────────────────────────────────────────────────

  Future<void> logout() async {
    final refreshToken = await tokenStorage.getRefreshToken();
    if (refreshToken != null) {
      try {
        await dio.delete<void>(
          '/api/v1/auth/logout',
          data: LogoutRequest(refreshToken: refreshToken).toJson(),
        );
      } on DioException catch (_) {
        // Best-effort — always clear tokens locally.
      }
    }
    await tokenStorage.clearTokens();
  }

  // ── Forgot password ───────────────────────────────────────────────────────

  Future<void> forgotPassword(String email) async {
    await dio.post<Map<String, dynamic>>(
      '/api/v1/auth/forgot-password',
      data: ForgotPasswordRequest(email: email).toJson(),
    );
  }

  // ── Reset password ────────────────────────────────────────────────────────

  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    await dio.post<void>(
      '/api/v1/auth/reset-password',
      data: ResetPasswordRequest(token: token, newPassword: newPassword).toJson(),
    );
  }

  // ── Delete account ────────────────────────────────────────────────────────

  Future<void> deleteAccount() async {
    await dio.delete<void>('/api/v1/auth/account');
    await tokenStorage.clearTokens();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Maps a [DioException] error code to a user-friendly message
  /// per CON-001 §5.1 and AGT-002-MB §4.5.
  static String mapError(DioException e) {
    final code = _extractCode(e);
    return switch (code) {
      'EMAIL_ALREADY_EXISTS' =>
        'An account with that email already exists. Try logging in.',
      'UNAUTHORIZED' => 'Invalid email or password.',
      'TOKEN_EXPIRED' => 'Your session has expired. Please log in again.',
      'TOKEN_INVALID' => 'The reset link is invalid or has already been used.',
      'REFRESH_TOKEN_EXPIRED' => 'Your session has expired. Please log in again.',
      'REFRESH_TOKEN_REVOKED' => 'Your session was revoked. Please log in again.',
      'VALIDATION_ERROR' =>
        'Please check your input and try again.',
      'RATE_LIMITED' => 'Too many attempts. Please wait a moment and try again.',
      _ => 'Something went wrong. Please try again.',
    };
  }

  static String _extractCode(DioException e) {
    try {
      final data = e.response?.data;
      if (data is Map<String, dynamic>) {
        return ApiError.fromJson(data).code;
      }
    } catch (_) {}
    return 'INTERNAL_ERROR';
  }
}
