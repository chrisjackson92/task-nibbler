import 'package:equatable/equatable.dart';

// ────────────────────────────────────────────────
// Enums (CON-002 §5 calculated fields)
// ────────────────────────────────────────────────

enum SpriteState { welcome, happy, neutral, sad }

enum TreeState { thriving, healthy, struggling, withering }

// ────────────────────────────────────────────────
// GamificationStateData — maps GET /gamification/state
// ────────────────────────────────────────────────

class GamificationStateData extends Equatable {
  const GamificationStateData({
    required this.streakCount,
    required this.lastActiveDate,
    required this.graceActive,
    required this.hasCompletedFirstTask,
    required this.treeHealthScore,
    required this.treeState,
    required this.spriteState,
    required this.totalBadgesEarned,
    this.spriteType = 'sprite_a',
    this.treeType = 'tree_a',
  });

  final int streakCount;
  final String? lastActiveDate; // "YYYY-MM-DD"
  final bool graceActive;
  final bool hasCompletedFirstTask;
  final int treeHealthScore; // 0–100
  final TreeState treeState;
  final SpriteState spriteState;
  final int totalBadgesEarned;
  final String spriteType; // 'sprite_a' | 'sprite_b'
  final String treeType;   // 'tree_a' | 'tree_b'

  factory GamificationStateData.fromJson(Map<String, dynamic> json) =>
      GamificationStateData(
        streakCount: json['streak_count'] as int,
        lastActiveDate: json['last_active_date'] as String?,
        graceActive: json['grace_active'] as bool,
        hasCompletedFirstTask: json['has_completed_first_task'] as bool,
        treeHealthScore: json['tree_health_score'] as int,
        treeState: _parseTreeState(json['tree_state'] as String),
        spriteState: _parseSpriteState(json['sprite_state'] as String),
        totalBadgesEarned: json['total_badges_earned'] as int? ?? 0,
        spriteType: json['sprite_type'] as String? ?? 'sprite_a',
        treeType: json['tree_type'] as String? ?? 'tree_a',
      );

  /// Applies a [GamificationDelta] from a task completion response,
  /// returning a new [GamificationStateData] without a full API round-trip.
  GamificationStateData applyDelta(GamificationDeltaData delta) {
    final newHealth = (treeHealthScore + delta.treeHealthDelta)
        .clamp(0, 100);
    return GamificationStateData(
      streakCount: delta.streakCount,
      lastActiveDate: lastActiveDate,
      graceActive: delta.graceActive,
      hasCompletedFirstTask: true,
      treeHealthScore: newHealth,
      treeState: _treeStateFor(newHealth),
      spriteState: _spriteStateFor(
        streakCount: delta.streakCount,
        treeHealthScore: newHealth,
        hasCompletedFirstTask: true,
      ),
      totalBadgesEarned: totalBadgesEarned + delta.badgesAwarded.length,
      spriteType: spriteType,
      treeType: treeType,
    );
  }

  static TreeState _parseTreeState(String raw) => switch (raw) {
        'THRIVING' => TreeState.thriving,
        'HEALTHY' => TreeState.healthy,
        'STRUGGLING' => TreeState.struggling,
        _ => TreeState.withering,
      };

  static SpriteState _parseSpriteState(String raw) => switch (raw) {
        'WELCOME' => SpriteState.welcome,
        'HAPPY' => SpriteState.happy,
        'NEUTRAL' => SpriteState.neutral,
        _ => SpriteState.sad,
      };

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

  @override
  List<Object?> get props => [
        streakCount,
        lastActiveDate,
        graceActive,
        hasCompletedFirstTask,
        treeHealthScore,
        treeState,
        spriteState,
        totalBadgesEarned,
        spriteType,
        treeType,
      ];
}

// ────────────────────────────────────────────────
// GamificationDeltaData — subset from task complete
// Used to update GamificationStateData without an API round-trip
// ────────────────────────────────────────────────

class GamificationDeltaData extends Equatable {
  const GamificationDeltaData({
    required this.streakCount,
    required this.treeHealthScore,
    required this.treeHealthDelta,
    required this.graceActive,
    required this.badgesAwarded,
  });

  final int streakCount;
  final int treeHealthScore;
  final int treeHealthDelta;
  final bool graceActive;
  final List<BadgeData> badgesAwarded;

  @override
  List<Object?> get props => [
        streakCount,
        treeHealthScore,
        treeHealthDelta,
        graceActive,
        badgesAwarded,
      ];
}

// ────────────────────────────────────────────────
// BadgeData — from GET /gamification/badges
// ────────────────────────────────────────────────

class BadgeData extends Equatable {
  const BadgeData({
    required this.id,
    required this.name,
    required this.emoji,
    required this.description,
    required this.triggerType,
    required this.earned,
    this.earnedAt,
  });

  final String id;
  final String name;
  final String emoji;
  final String description;
  final String triggerType;
  final bool earned;
  final DateTime? earnedAt;

  factory BadgeData.fromJson(Map<String, dynamic> json) => BadgeData(
        id: json['id'] as String,
        name: json['name'] as String,
        emoji: json['emoji'] as String,
        description: json['description'] as String,
        triggerType: json['trigger_type'] as String,
        earned: json['earned'] as bool,
        earnedAt: json['earned_at'] != null
            ? DateTime.parse(json['earned_at'] as String)
            : null,
      );

  @override
  List<Object?> get props =>
      [id, name, emoji, description, triggerType, earned, earnedAt];
}

/// The full 14 badge catalogue (BLU-002-SD §2) — used for badge shelf
/// ordering. The API returns all 14; we use this canonical list to ensure
/// consistent display order even if the API order changes.
const List<String> kBadgeDisplayOrder = [
  'FIRST_NIBBLE',
  'STREAK_7',
  'STREAK_14',
  'STREAK_30',
  'STREAK_100',
  'STREAK_365',
  'CONSISTENT_WEEK',
  'CONSISTENT_MONTH',
  'PRODUCTIVE_WEEK',
  'PRODUCTIVE_MONTH',
  'OVERACHIEVER',
  'TREE_HEALTHY',
  'TREE_THRIVING',
  'TREE_SUSTAINED',
];
