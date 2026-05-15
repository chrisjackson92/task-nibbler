import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/api/models/gamification_models.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../gamification/bloc/gamification_cubit.dart';

/// Hero section displayed in the collapsible SliverAppBar (M-035).
/// Adapts to all gamification states.
class HeroSection extends StatelessWidget {
  const HeroSection({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GamificationCubit, GamificationState>(
      builder: (context, state) => switch (state) {
        GamificationInitial() ||
        GamificationLoading() =>
          const _HeroLoading(),
        GamificationLoaded(gamState: final g) =>
          _HeroContent(gamState: g),
        GamificationBadgeAwarded(gamState: final g) =>
          _HeroContent(gamState: g),
        GamificationError() => const _HeroError(),
      },
    );
  }
}

// ── Loading ───────────────────────────────────────────────────────────────────

class _HeroLoading extends StatelessWidget {
  const _HeroLoading();
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.heroGradientStart, AppColors.heroGradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: CircularProgressIndicator(
          color: Colors.white54,
          strokeWidth: 2,
        ),
      ),
    );
  }
}

// ── Error ─────────────────────────────────────────────────────────────────────

class _HeroError extends StatelessWidget {
  const _HeroError();
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.heroGradientStart, AppColors.heroGradientEnd],
        ),
      ),
      child: const Center(
        child: Text(
          'Could not load stats',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ),
    );
  }
}

// ── Loaded ────────────────────────────────────────────────────────────────────

class _HeroContent extends StatelessWidget {
  const _HeroContent({required this.gamState});
  final GamificationStateData gamState;

  @override
  Widget build(BuildContext context) {
    final isWelcome = gamState.spriteState == SpriteState.welcome;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.heroGradientStart, AppColors.heroGradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          // Left: streak counter
          Expanded(
            child: isWelcome ? const _WelcomeMessage() : _StreakColumn(gamState: gamState),
          ),
          // Right: tree health meter
          if (!isWelcome)
            _TreeHealthColumn(gamState: gamState),
        ],
      ),
    );
  }
}

class _WelcomeMessage extends StatelessWidget {
  const _WelcomeMessage();
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Welcome to Task Nibbles!',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Complete your first task to start your streak.',
          style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
        ),
      ],
    );
  }
}

class _StreakColumn extends StatelessWidget {
  const _StreakColumn({required this.gamState});
  final GamificationStateData gamState;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('🔥', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 6),
            Text(
              key: const Key('hero_streak_count'),
              '${gamState.streakCount}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 4),
            const Text('day streak',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
            // Grace indicator (M-035)
            if (gamState.graceActive) ...[
              const SizedBox(width: 6),
              const Tooltip(
                message: 'Grace day active — streak protected!',
                child: Icon(
                  Icons.bolt_rounded,
                  color: Color(0xFFFFD600),
                  size: 18,
                  key: Key('hero_grace_indicator'),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          _spriteLabel(gamState.spriteState),
          style: TextStyle(
              color: Colors.white.withOpacity(0.75), fontSize: 11),
        ),
      ],
    );
  }

  String _spriteLabel(SpriteState state) => switch (state) {
        SpriteState.happy => 'Your companion is cheering! 😊',
        SpriteState.neutral => 'Keep going — stay consistent! 😐',
        SpriteState.sad => 'Your companion needs you. Start a task! 😢',
        SpriteState.welcome => '',
      };
}

class _TreeHealthColumn extends StatelessWidget {
  const _TreeHealthColumn({required this.gamState});
  final GamificationStateData gamState;

  @override
  Widget build(BuildContext context) {
    final treeEmoji = switch (gamState.treeState) {
      TreeState.thriving => '🌳',
      TreeState.healthy => '🌿',
      TreeState.struggling => '🍂',
      TreeState.withering => '🪨',
    };

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(treeEmoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 6),
            Text(
              key: const Key('hero_tree_health'),
              '${gamState.treeHealthScore}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Text('/100',
                style: TextStyle(color: Colors.white60, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 90,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              key: const Key('hero_health_bar'),
              value: gamState.treeHealthScore / 100,
              minHeight: 5,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _treeLabel(gamState.treeState),
          style: const TextStyle(color: Colors.white70, fontSize: 10),
        ),
      ],
    );
  }

  String _treeLabel(TreeState t) => switch (t) {
        TreeState.thriving => 'THRIVING',
        TreeState.healthy => 'HEALTHY',
        TreeState.struggling => 'STRUGGLING',
        TreeState.withering => 'WITHERING',
      };
}
