import 'package:equatable/equatable.dart';

import '../../../core/api/models/auth_models.dart';

/// Auth state hierarchy using sealed classes (GOV-011 §7.1, AGT-002-MB §4.3).
sealed class AuthState extends Equatable {
  const AuthState();
  @override
  List<Object?> get props => [];
}

/// Initial state before any auth check is performed.
final class AuthInitial extends AuthState {
  const AuthInitial();
}

/// Session is being restored from stored tokens on app startup.
final class AuthRestoring extends AuthState {
  const AuthRestoring();
}

/// Auth operation in progress (login, register, logout, delete).
final class AuthLoading extends AuthState {
  const AuthLoading();
}

/// User is authenticated.
final class AuthAuthenticated extends AuthState {
  const AuthAuthenticated({required this.user});
  final AuthUser user;
  @override
  List<Object?> get props => [user];
}

/// User is not authenticated (logged out, token expired, never logged in).
final class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

/// An auth operation failed. [message] is user-displayable.
final class AuthError extends AuthState {
  const AuthError(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}

/// Forgot password email submitted successfully.
final class AuthForgotPasswordSent extends AuthState {
  const AuthForgotPasswordSent();
}

/// Password reset completed — user should navigate to login.
final class AuthPasswordResetComplete extends AuthState {
  const AuthPasswordResetComplete();
}
