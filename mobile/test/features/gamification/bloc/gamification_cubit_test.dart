import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:task_nibbles/core/api/models/gamification_models.dart';
import 'package:task_nibbles/core/api/models/task_models.dart';
import 'package:task_nibbles/features/gamification/bloc/gamification_cubit.dart';
import 'package:task_nibbles/features/gamification/data/gamification_repository.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class MockGamificationRepository extends Mock
    implements GamificationRepository {}

// ── Test data ─────────────────────────────────────────────────────────────────

final _defaultState = const GamificationStateData(
  streakCount: 5,
  lastActiveDate: '2026-05-15',
  graceActive: false,
  hasCompletedFirstTask: true,
  treeHealthScore: 70,
  treeState: TreeState.healthy,
  spriteState: SpriteState.happy,
  totalBadgesEarned: 2,
);

const _defaultBadge = BadgeData(
  id: 'STREAK_7',
  name: 'Week Warrior',
  emoji: '🔥',
  description: 'You maintained a 7-day streak.',
  triggerType: 'STREAK_MILESTONE',
  earned: true,
);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late MockGamificationRepository mockRepo;

  setUp(() {
    mockRepo = MockGamificationRepository();
  });

  GamificationCubit buildCubit() => GamificationCubit(repository: mockRepo);

  // ── 1. loadState success → GamificationLoaded ─────────────────────────────

  group('GamificationCubit — loadState', () {
    blocTest<GamificationCubit, GamificationState>(
      'success → [Loading, Loaded]',
      build: buildCubit,
      setUp: () {
        when(() => mockRepo.getState())
            .thenAnswer((_) async => _defaultState);
        when(() => mockRepo.getBadges())
            .thenAnswer((_) async => [_defaultBadge]);
      },
      act: (c) => c.loadState(),
      expect: () => [
        isA<GamificationLoading>(),
        isA<GamificationLoaded>().having(
          (s) => s.gamState.streakCount,
          'streakCount',
          5,
        ),
      ],
    );

    blocTest<GamificationCubit, GamificationState>(
      'API error → [Loading, GamificationError]',
      build: buildCubit,
      setUp: () {
        when(() => mockRepo.getState()).thenThrow(
          const GamificationRepositoryException('Network error'),
        );
        when(() => mockRepo.getBadges())
            .thenAnswer((_) async => []);
      },
      act: (c) => c.loadState(),
      expect: () => [
        isA<GamificationLoading>(),
        isA<GamificationError>(),
      ],
    );
  });

  // ── 2. applyDelta → updates streak and tree health ────────────────────────

  group('GamificationCubit — applyDelta', () {
    blocTest<GamificationCubit, GamificationState>(
      'applyDelta → updates streak and tree health in Loaded state',
      build: buildCubit,
      seed: () => GamificationLoaded(
        gamState: _defaultState,
        badges: const [_defaultBadge],
      ),
      act: (c) => c.applyDelta(const GamificationDelta(
        streakCount: 6,
        treeHealthScore: 75,
        treeHealthDelta: 5,
        graceActive: false,
        badgesAwarded: [],
      )),
      expect: () => [
        isA<GamificationLoaded>()
            .having((s) => s.gamState.streakCount, 'streakCount', 6)
            .having(
                (s) => s.gamState.treeHealthScore, 'treeHealthScore', 75),
      ],
    );

    // ── 3. applyDelta with badge → GamificationBadgeAwarded ─────────────────

    blocTest<GamificationCubit, GamificationState>(
      'applyDelta with badge → emits GamificationBadgeAwarded then GamificationLoaded',
      build: buildCubit,
      seed: () => GamificationLoaded(
        gamState: _defaultState,
        badges: const [],
      ),
      act: (c) => c.applyDelta(const GamificationDelta(
        streakCount: 7,
        treeHealthScore: 80,
        treeHealthDelta: 10,
        graceActive: false,
        badgesAwarded: [
          BadgeAward(
            id: 'STREAK_7',
            name: 'Week Warrior',
            emoji: '🔥',
            description: 'You maintained a 7-day streak.',
          ),
        ],
      )),
      expect: () => [
        isA<GamificationBadgeAwarded>().having(
          (s) => s.badge.id,
          'badge.id',
          'STREAK_7',
        ),
        isA<GamificationLoaded>(),
      ],
    );

    // ── 4. WELCOME state → sprite_state = WELCOME ────────────────────────────

    blocTest<GamificationCubit, GamificationState>(
      'loadState with has_completed_first_task=false → sprite_state = WELCOME',
      build: buildCubit,
      setUp: () {
        when(() => mockRepo.getState()).thenAnswer((_) async =>
            const GamificationStateData(
              streakCount: 0,
              lastActiveDate: null,
              graceActive: false,
              hasCompletedFirstTask: false,
              treeHealthScore: 50,
              treeState: TreeState.healthy,
              spriteState: SpriteState.welcome,
              totalBadgesEarned: 0,
            ));
        when(() => mockRepo.getBadges()).thenAnswer((_) async => []);
      },
      act: (c) => c.loadState(),
      expect: () => [
        isA<GamificationLoading>(),
        isA<GamificationLoaded>().having(
          (s) => s.gamState.spriteState,
          'spriteState',
          SpriteState.welcome,
        ),
      ],
    );
  });
}
