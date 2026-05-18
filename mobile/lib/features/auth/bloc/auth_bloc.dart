import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/cache/task_cache.dart';
import '../../../core/notifications/notification_permission_service.dart';
import '../data/auth_repository.dart';
import '../../../core/api/models/auth_models.dart';
import 'auth_state.dart';

// ──────────────────────────────────────────────
// Events
// ──────────────────────────────────────────────

sealed class AuthEvent {
  const AuthEvent();
}

final class AuthLoginRequested extends AuthEvent {
  const AuthLoginRequested({
    required this.email,
    required this.password,
    this.rememberMe = true,
  });
  final String email;
  final String password;
  final bool rememberMe;
}

final class AuthRegisterRequested extends AuthEvent {
  const AuthRegisterRequested({required this.email, required this.password});
  final String email;
  final String password;
}

final class AuthLogoutRequested extends AuthEvent {
  const AuthLogoutRequested();
}

final class AuthDeleteAccountRequested extends AuthEvent {
  const AuthDeleteAccountRequested();
}

/// Fired by [AuthInterceptor] when a silent refresh fails.
final class AuthTokenExpired extends AuthEvent {
  const AuthTokenExpired();
}

final class AuthForgotPasswordRequested extends AuthEvent {
  const AuthForgotPasswordRequested({required this.email});
  final String email;
}

final class AuthResetPasswordRequested extends AuthEvent {
  const AuthResetPasswordRequested({
    required this.token,
    required this.newPassword,
  });
  final String token;
  final String newPassword;
}

/// Fired on app startup to restore session from stored refresh token.
final class AuthRestoreSessionRequested extends AuthEvent {
  const AuthRestoreSessionRequested();
}

/// Fired after a successful profile update (e.g. timezone change).
final class AuthProfileUpdated extends AuthEvent {
  const AuthProfileUpdated({required this.user});
  final AuthUser user;
}

// ──────────────────────────────────────────────
// BLoC
// ──────────────────────────────────────────────

/// Manages all authentication state (login, register, logout, delete, refresh).
/// Uses BLoC (not Cubit) because of multiple distinct event types with
/// different business logic paths (AGT-002-MB §4.2, BLU-004 §3).
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({
    required AuthRepository authRepository,
    required TaskCache taskCache,
  })  : _authRepository = authRepository,
        _taskCache = taskCache,
        super(const AuthInitial()) {
    on<AuthLoginRequested>(_onLoginRequested);
    on<AuthRegisterRequested>(_onRegisterRequested);
    on<AuthLogoutRequested>(_onLogoutRequested);
    on<AuthDeleteAccountRequested>(_onDeleteAccountRequested);
    on<AuthTokenExpired>(_onTokenExpired);
    on<AuthForgotPasswordRequested>(_onForgotPasswordRequested);
    on<AuthResetPasswordRequested>(_onResetPasswordRequested);
    on<AuthRestoreSessionRequested>(_onRestoreSession);
    on<AuthProfileUpdated>(_onProfileUpdated);
  }

  final AuthRepository _authRepository;
  final TaskCache _taskCache;

  // ── Handlers ──────────────────────────────────────────────────────────────

  Future<void> _onLoginRequested(
    AuthLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    try {
      final response = await _authRepository.login(
        LoginRequest(email: event.email, password: event.password),
        rememberMe: event.rememberMe,
      );
      emit(AuthAuthenticated(user: response.user));
      // M-054: request notification permission after successful login (fire & forget).
      NotificationPermissionService.requestIfNeeded();
    } on DioException catch (e) {
      emit(AuthError(AuthRepository.mapError(e)));
    }
  }

  Future<void> _onRegisterRequested(
    AuthRegisterRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    try {
      final response = await _authRepository.register(
        RegisterRequest(email: event.email, password: event.password),
      );
      emit(AuthAuthenticated(user: response.user));
      // M-054: request notification permission after successful register (fire & forget).
      NotificationPermissionService.requestIfNeeded();
    } on DioException catch (e) {
      emit(AuthError(AuthRepository.mapError(e)));
    }
  }

  Future<void> _onLogoutRequested(
    AuthLogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    await _authRepository.logout();
    await _taskCache.clear(); // GOV-011 §5.4
    emit(const AuthUnauthenticated());
  }

  Future<void> _onDeleteAccountRequested(
    AuthDeleteAccountRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    try {
      await _authRepository.deleteAccount();
      await _taskCache.clear();
      emit(const AuthUnauthenticated());
    } on DioException catch (e) {
      emit(AuthError(AuthRepository.mapError(e)));
    }
  }

  Future<void> _onTokenExpired(
    AuthTokenExpired event,
    Emitter<AuthState> emit,
  ) async {
    // Silent refresh has already failed in AuthInterceptor.
    // Clear local state and redirect to login.
    await _taskCache.clear();
    emit(const AuthUnauthenticated());
  }

  Future<void> _onForgotPasswordRequested(
    AuthForgotPasswordRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    try {
      await _authRepository.forgotPassword(event.email);
      emit(const AuthForgotPasswordSent());
    } on DioException catch (e) {
      emit(AuthError(AuthRepository.mapError(e)));
    }
  }

  Future<void> _onResetPasswordRequested(
    AuthResetPasswordRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    try {
      await _authRepository.resetPassword(
        token: event.token,
        newPassword: event.newPassword,
      );
      emit(const AuthPasswordResetComplete());
    } on DioException catch (e) {
      emit(AuthError(AuthRepository.mapError(e)));
    }
  }

  /// Restores session on app startup by exchanging stored refresh token.
  /// Emits [AuthRestoring] while in progress, then [AuthAuthenticated] or
  /// [AuthUnauthenticated]. Silent — never emits [AuthError].
  Future<void> _onRestoreSession(
    AuthRestoreSessionRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthRestoring());
    try {
      final auth = await _authRepository.restoreSession();
      if (auth != null) {
        emit(AuthAuthenticated(user: auth.user));
      } else {
        emit(const AuthUnauthenticated());
      }
    } catch (_) {
      emit(const AuthUnauthenticated());
    }
  }

  /// Updates the in-memory user after a successful profile PATCH.
  void _onProfileUpdated(
    AuthProfileUpdated event,
    Emitter<AuthState> emit,
  ) {
    emit(AuthAuthenticated(user: event.user));
  }
}
