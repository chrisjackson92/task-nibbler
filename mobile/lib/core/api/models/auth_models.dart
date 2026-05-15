import 'package:equatable/equatable.dart';

// ──────────────────────────────────────────────
// Shared sub-models
// ──────────────────────────────────────────────

/// A logged-in user returned by auth endpoints (CON-002 §1).
class AuthUser extends Equatable {
  const AuthUser({
    required this.id,
    required this.email,
    required this.timezone,
    required this.createdAt,
  });

  final String id;
  final String email;
  final String timezone;
  final DateTime createdAt;

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String,
        email: json['email'] as String,
        timezone: json['timezone'] as String? ?? 'UTC',
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  @override
  List<Object?> get props => [id, email, timezone, createdAt];
}

// ──────────────────────────────────────────────
// Request models
// ──────────────────────────────────────────────

class LoginRequest {
  const LoginRequest({required this.email, required this.password});

  final String email;
  final String password;

  Map<String, dynamic> toJson() => {
        'email': email,
        'password': password,
      };
}

class RegisterRequest {
  const RegisterRequest({
    required this.email,
    required this.password,
    this.timezone = 'UTC',
  });

  final String email;
  final String password;
  final String timezone;

  Map<String, dynamic> toJson() => {
        'email': email,
        'password': password,
        'timezone': timezone,
      };
}

class RefreshRequest {
  const RefreshRequest({required this.refreshToken});
  final String refreshToken;

  Map<String, dynamic> toJson() => {'refresh_token': refreshToken};
}

class ForgotPasswordRequest {
  const ForgotPasswordRequest({required this.email});
  final String email;

  Map<String, dynamic> toJson() => {'email': email};
}

class ResetPasswordRequest {
  const ResetPasswordRequest({
    required this.token,
    required this.newPassword,
  });

  final String token;
  final String newPassword;

  Map<String, dynamic> toJson() => {
        'token': token,
        'new_password': newPassword,
      };
}

class LogoutRequest {
  const LogoutRequest({required this.refreshToken});
  final String refreshToken;

  Map<String, dynamic> toJson() => {'refresh_token': refreshToken};
}

// ──────────────────────────────────────────────
// Response models
// ──────────────────────────────────────────────

/// Returned by POST /auth/login and POST /auth/register (CON-002 §1).
class AuthResponse extends Equatable {
  const AuthResponse({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
  });

  final AuthUser user;
  final String accessToken;
  final String refreshToken;

  factory AuthResponse.fromJson(Map<String, dynamic> json) => AuthResponse(
        user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
      );

  @override
  List<Object?> get props => [user, accessToken, refreshToken];
}

/// Returned by POST /auth/refresh (CON-002 §1).
class RefreshResponse extends Equatable {
  const RefreshResponse({
    required this.accessToken,
    required this.refreshToken,
  });

  final String accessToken;
  final String refreshToken;

  factory RefreshResponse.fromJson(Map<String, dynamic> json) =>
      RefreshResponse(
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
      );

  @override
  List<Object?> get props => [accessToken, refreshToken];
}
