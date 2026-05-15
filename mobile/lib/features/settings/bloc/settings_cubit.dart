import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../auth/bloc/auth_bloc.dart';

// ──────────────────────────────────────────────
// State
// ──────────────────────────────────────────────

sealed class SettingsState extends Equatable {
  const SettingsState();
  @override
  List<Object?> get props => [];
}

final class SettingsIdle extends SettingsState {
  const SettingsIdle();
}

final class SettingsLoading extends SettingsState {
  const SettingsLoading();
}

final class SettingsError extends SettingsState {
  const SettingsError(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}

// ──────────────────────────────────────────────
// Cubit (M-010)
// ──────────────────────────────────────────────

/// Manages logout and delete-account flows.
/// Uses Cubit (not BLoC) — two simple linear actions (AGT-002-MB §4.2).
/// Delegates actual business logic to [AuthBloc] to keep token management
/// centralised.
class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit({required AuthBloc authBloc})
      : _authBloc = authBloc,
        super(const SettingsIdle());

  final AuthBloc _authBloc;

  void logout() {
    emit(const SettingsLoading());
    _authBloc.add(const AuthLogoutRequested());
    // AuthBloc handles navigation via go_router redirect.
    emit(const SettingsIdle());
  }

  void deleteAccount() {
    emit(const SettingsLoading());
    _authBloc.add(const AuthDeleteAccountRequested());
    emit(const SettingsIdle());
  }
}
