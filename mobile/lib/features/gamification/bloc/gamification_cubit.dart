import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

// ──────────────────────────────────────────────
// State
// ──────────────────────────────────────────────

sealed class GamificationState extends Equatable {
  const GamificationState();
  @override
  List<Object?> get props => [];
}

/// Welcome state — user hasn't completed their first task yet.
final class GamificationWelcome extends GamificationState {
  const GamificationWelcome();
}

/// Sprint 1 placeholder for loaded gamification state.
final class GamificationLoaded extends GamificationState {
  const GamificationLoaded({
    required this.streakCount,
    required this.treeHealthScore,
    required this.treeState,
    required this.spriteState,
    required this.graceActive,
  });

  final int streakCount;
  final int treeHealthScore;
  final String treeState;
  final String spriteState;
  final bool graceActive;

  @override
  List<Object?> get props => [
        streakCount,
        treeHealthScore,
        treeState,
        spriteState,
        graceActive,
      ];
}

// ──────────────────────────────────────────────
// Cubit (M-013)
// ──────────────────────────────────────────────

/// Sprint 1: emits [GamificationWelcome] only.
/// Real gamification data fetch is implemented in SPR-004-MB.
/// Interface is correct — just swap the placeholder for a real API call later.
class GamificationCubit extends Cubit<GamificationState> {
  GamificationCubit() : super(const GamificationWelcome());

  /// Called when gamification data should be refreshed (Sprint 4 implementation).
  Future<void> refresh() async {
    // Sprint 1: no-op. Sprint 4: call GET /gamification/state.
  }
}
