import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/api/models/task_models.dart';

// ──────────────────────────────────────────────
// State
// ──────────────────────────────────────────────

sealed class GamificationState extends Equatable {
  const GamificationState();
}

/// Shown until first task is completed (PRJ-001 §5.5).
class GamificationWelcome extends GamificationState {
  const GamificationWelcome();

  @override
  List<Object?> get props => [];
}

/// Emitted once real data is available — either from a complete response
/// (SPR-002-MB) or from the gamification API (SPR-004-MB).
class GamificationLoaded extends GamificationState {
  const GamificationLoaded({
    required this.streakCount,
    required this.treeHealthScore,
    required this.graceActive,
    required this.earnedBadges,
  });

  final int streakCount;
  final int treeHealthScore;
  final bool graceActive;
  final List<BadgeAward> earnedBadges;

  @override
  List<Object?> get props =>
      [streakCount, treeHealthScore, graceActive, earnedBadges];
}

// ──────────────────────────────────────────────
// Cubit
// ──────────────────────────────────────────────

/// Manages the gamification hero section state.
///
/// Sprint 1–3: starts in [GamificationWelcome].
/// [applyDelta] updates to [GamificationLoaded] after any task completion.
/// Sprint 4: `refresh()` will call GET /gamification to hydrate on app boot.
class GamificationCubit extends Cubit<GamificationState> {
  GamificationCubit() : super(const GamificationWelcome());

  /// Called by [TaskListBloc] after a successful `POST /tasks/:id/complete`.
  /// Transitions from WELCOME → LOADED on first completion.
  void applyDelta(GamificationDelta delta) {
    final current = state;
    final existingBadges = current is GamificationLoaded
        ? current.earnedBadges
        : <BadgeAward>[];

    // Merge newly awarded badges into accumulated badge list (deduplicated).
    final merged = [
      ...existingBadges,
      ...delta.badgesAwarded.where(
        (b) => !existingBadges.any((e) => e.id == b.id),
      ),
    ];

    emit(GamificationLoaded(
      streakCount: delta.streakCount,
      treeHealthScore: delta.treeHealthScore,
      graceActive: delta.graceActive,
      earnedBadges: merged,
    ));
  }

  /// No-op stub until Sprint 4 implements the gamification API endpoint.
  Future<void> refresh() async {}
}
