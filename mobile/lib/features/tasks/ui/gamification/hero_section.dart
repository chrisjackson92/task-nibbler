import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api/models/gamification_models.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../gamification/bloc/gamification_cubit.dart';
import '../../../gamification/ui/widgets/sprite_widget.dart';
import '../../../gamification/ui/widgets/tree_widget.dart';

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
    final health = gamState.treeHealthScore;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.heroGradientStart, AppColors.heroGradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // ── Sprite (tap to pick) ─────────────────────────────────────────────
          GestureDetector(
            onTap: () => context.push(AppRoutes.companionPicker),
            child: Tooltip(
              message: 'Change companion',
              child: _buildSprite(gamState.spriteType, health),
            ),
          ),
          const SizedBox(width: 12),

          // ── Stats ────────────────────────────────────────────────────────────
          Expanded(
            child: isWelcome
                ? const _WelcomeMessage()
                : _StreakColumn(gamState: gamState),
          ),

          // ── Tree (tap to pick) ───────────────────────────────────────────────
          if (!isWelcome) ...[
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () => context.push(AppRoutes.companionPicker),
              child: Tooltip(
                message: 'Change tree',
                child: _buildTree(gamState.treeType, health),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSprite(String type, int health) => SizedBox(
        width: 56,
        height: 56,
        child: type == 'sprite_b'
            ? SpriteBWidget(healthScore: health, size: 56)
            : SpriteAWidget(healthScore: health, size: 56),
      );

  Widget _buildTree(String type, int health) => SizedBox(
        width: 52,
        height: 64,
        child: type == 'tree_b'
            ? TreeBWidget(healthScore: health, size: 64)
            : TreeAWidget(healthScore: health, size: 64),
      );
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

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
            fontSize: 15,
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
            const Text('🔥', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 4),
            Text(
              key: const Key('hero_streak_count'),
              '${gamState.streakCount}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 4),
            const Text('day streak',
                style: TextStyle(color: Colors.white70, fontSize: 11)),
            if (gamState.graceActive) ...[
              const SizedBox(width: 4),
              const Tooltip(
                message: 'Grace day active — streak protected!',
                child: Icon(
                  Icons.bolt_rounded,
                  color: Color(0xFFFFD600),
                  size: 16,
                  key: Key('hero_grace_indicator'),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 100,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              key: const Key('hero_health_bar'),
              value: gamState.treeHealthScore / 100,
              minHeight: 4,
              backgroundColor: Colors.white24,
              valueColor: AlwaysStoppedAnimation(
                CompanionHealth.fromScore(gamState.treeHealthScore).primaryColor,
              ),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${gamState.treeHealthScore}/100 · '
          '${CompanionHealth.fromScore(gamState.treeHealthScore).label}',
          style: const TextStyle(color: Colors.white70, fontSize: 10),
        ),
      ],
    );
  }
}
