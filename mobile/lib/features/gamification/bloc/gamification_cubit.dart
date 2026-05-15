import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api/models/gamification_models.dart';
import '../../../core/api/models/task_models.dart' show GamificationDelta;
import '../data/gamification_repository.dart';

// ──────────────────────────────────────────────────────────────────────────────
// States
// ──────────────────────────────────────────────────────────────────────────────

sealed class GamificationState extends Equatable {
  const GamificationState();
}

/// App opened, API call in-flight or first-render.
class GamificationInitial extends GamificationState {
  const GamificationInitial();
  @override
  List<Object?> get props => [];
}

class GamificationLoading extends GamificationState {
  const GamificationLoading();
  @override
  List<Object?> get props => [];
}

/// Normal running state — shows hero + badge shelf data.
class GamificationLoaded extends GamificationState {
  const GamificationLoaded({
    required this.gamState,
    required this.badges,
  });

  final GamificationStateData gamState;
  final List<BadgeData> badges;

  GamificationLoaded copyWith({
    GamificationStateData? gamState,
    List<BadgeData>? badges,
  }) =>
      GamificationLoaded(
        gamState: gamState ?? this.gamState,
        badges: badges ?? this.badges,
      );

  @override
  List<Object?> get props => [gamState, badges];
}

/// Emitted for ONE frame after a badge is awarded — drives the overlay.
/// Immediately followed by [GamificationLoaded] on the next cycle.
class GamificationBadgeAwarded extends GamificationState {
  const GamificationBadgeAwarded({
    required this.badge,
    required this.gamState,
    required this.badges,
  });

  final BadgeData badge; // the newly awarded badge to celebrate
  final GamificationStateData gamState;
  final List<BadgeData> badges;

  @override
  List<Object?> get props => [badge, gamState, badges];
}

class GamificationError extends GamificationState {
  const GamificationError(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}

// ──────────────────────────────────────────────────────────────────────────────
// Cubit
// ──────────────────────────────────────────────────────────────────────────────

/// Manages the full gamification state:
///   - `loadState()` — called on app open; hydrates from API
///   - `applyDelta()` — called after task completion (no extra API round-trip)
///   - badge overlay emitted on badge unlock, then immediately reverted to Loaded
class GamificationCubit extends Cubit<GamificationState> {
  GamificationCubit({required this.repository})
      : super(const GamificationInitial());

  final GamificationRepository repository;

  // ── Load ────────────────────────────────────────────────────────────────────

  /// Called on app launch and after pull-to-refresh on the hero section.
  /// Fetches both GET /gamification/state and GET /gamification/badges in parallel.
  Future<void> loadState() async {
    emit(const GamificationLoading());
    try {
      final results = await Future.wait([
        repository.getState(),
        repository.getBadges(),
      ]);
      emit(GamificationLoaded(
        gamState: results[0] as GamificationStateData,
        badges: results[1] as List<BadgeData>,
      ));
    } on GamificationRepositoryException catch (e) {
      emit(GamificationError(e.message));
    } catch (_) {
      emit(const GamificationError('Failed to load gamification data.'));
    }
  }

  // ── Delta (after task completion) ──────────────────────────────────────────

  /// Called by [TaskListBloc] after a successful `POST /tasks/:id/complete`
  /// with the [GamificationDelta] from the response.
  ///
  /// Updates state locally — no API round-trip needed.
  /// If badges are awarded, emits [GamificationBadgeAwarded] for each
  /// new badge then returns to [GamificationLoaded].
  void applyDelta(GamificationDelta delta) {
    final current = state;

    // Build a GamificationStateData from the current state or make a new one
    // if we're still in Initial/Loading (first completion before API load).
    final GamificationStateData currentData;
    final List<BadgeData> currentBadges;

    if (current is GamificationLoaded) {
      currentData = current.gamState;
      currentBadges = current.badges;
    } else if (current is GamificationBadgeAwarded) {
      currentData = current.gamState;
      currentBadges = current.badges;
    } else {
      // First completion before API load — synthesize a baseline.
      currentData = GamificationStateData(
        streakCount: delta.streakCount,
        lastActiveDate: null,
        graceActive: delta.graceActive,
        hasCompletedFirstTask: true,
        treeHealthScore: delta.treeHealthScore,
        treeState: _treeStateFor(delta.treeHealthScore),
        spriteState: _spriteStateFor(
          streakCount: delta.streakCount,
          treeHealthScore: delta.treeHealthScore,
          hasCompletedFirstTask: true,
        ),
        totalBadgesEarned: delta.badgesAwarded.length,
      );
      currentBadges = const [];
    }

    // Create a delta adapter from task_models.GamificationDelta.
    final deltaData = GamificationDeltaData(
      streakCount: delta.streakCount,
      treeHealthScore: delta.treeHealthScore,
      treeHealthDelta: delta.treeHealthDelta,
      graceActive: delta.graceActive,
      badgesAwarded: delta.badgesAwarded
          .map((b) => BadgeData(
                id: b.id,
                name: b.name,
                emoji: b.emoji,
                description: '',
                triggerType: '',
                earned: true,
                earnedAt: b.awardedAt,
              ))
          .toList(),
    );

    final updatedData = currentData.applyDelta(deltaData);

    // Update the badge list with newly awarded badges marked as earned.
    final updatedBadges = _mergeBadges(currentBadges, deltaData.badgesAwarded);

    // Emit badge award overlay for EACH newly awarded badge, then settle on Loaded.
    final newBadges = deltaData.badgesAwarded;
    if (newBadges.isNotEmpty) {
      for (final badge in newBadges) {
        emit(GamificationBadgeAwarded(
          badge: badge,
          gamState: updatedData,
          badges: updatedBadges,
        ));
      }
    }

    emit(GamificationLoaded(gamState: updatedData, badges: updatedBadges));
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  List<BadgeData> _mergeBadges(
    List<BadgeData> existing,
    List<BadgeData> awarded,
  ) {
    if (awarded.isEmpty) return existing;
    final awardedIds = {for (final b in awarded) b.id};
    final merged = existing
        .map((b) => awardedIds.contains(b.id)
            ? BadgeData(
                id: b.id,
                name: b.name,
                emoji: b.emoji,
                description: b.description,
                triggerType: b.triggerType,
                earned: true,
                earnedAt: awarded.firstWhere((a) => a.id == b.id).earnedAt,
              )
            : b)
        .toList();
    // Add any awarded badges not already on the shelf (in case API list hasn't loaded).
    for (final a in awarded) {
      if (!merged.any((b) => b.id == a.id)) merged.add(a);
    }
    return merged;
  }

  static TreeState _treeStateFor(int health) {
    if (health >= 75) return TreeState.thriving;
    if (health >= 50) return TreeState.healthy;
    if (health >= 25) return TreeState.struggling;
    return TreeState.withering;
  }

  static SpriteState _spriteStateFor({
    required int streakCount,
    required int treeHealthScore,
    required bool hasCompletedFirstTask,
  }) {
    if (!hasCompletedFirstTask) return SpriteState.welcome;
    if (streakCount >= 1 && treeHealthScore >= 60) return SpriteState.happy;
    if (streakCount >= 1 && treeHealthScore >= 30) return SpriteState.neutral;
    return SpriteState.sad;
  }
}
