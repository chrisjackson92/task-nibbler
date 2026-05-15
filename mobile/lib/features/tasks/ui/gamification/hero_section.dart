import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../gamification/bloc/gamification_cubit.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';

/// Collapsible gamification hero section shown at the top of the task list
/// (BLU-004 §8, M-013, updated M-019).
///
/// Sprint 1–3: shows static values from [GamificationLoaded];
/// Sprint 4:   Rive animation replaces the icon placeholder.
class HeroSection extends StatelessWidget {
  const HeroSection({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GamificationCubit, GamificationState>(
      builder: (context, state) => GestureDetector(
        onTap: () => context.push(AppRoutes.gamification),
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.heroGradientStart, AppColors.heroGradientEnd],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.heroGradientStart.withOpacity(0.3),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: switch (state) {
            GamificationWelcome() => _WelcomeContent(),
            GamificationLoaded(
              streakCount: final streak,
              treeHealthScore: final health,
              graceActive: final grace,
            ) =>
              _LoadedContent(
                streakCount: streak,
                treeHealthScore: health,
                graceActive: grace,
              ),
          },
        ),
      ),
    );
  }
}

// ── Welcome state (before first task completion) ──────────────────────────────

class _WelcomeContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _SpritePlaceholder(emoji: '🌱', size: 52),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome to Task Nibbles!',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Complete your first task to start your streak.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white.withOpacity(0.85),
                    ),
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded, color: Colors.white54),
      ],
    );
  }
}

// ── Loaded state (after first completion) ─────────────────────────────────────

class _LoadedContent extends StatelessWidget {
  const _LoadedContent({
    required this.streakCount,
    required this.treeHealthScore,
    required this.graceActive,
  });

  final int streakCount;
  final int treeHealthScore;
  final bool graceActive;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _SpritePlaceholder(emoji: '🌳', size: 52),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Streak counter
              Row(
                children: [
                  Text(
                    '$streakCount day${streakCount == 1 ? '' : 's'} streak',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  if (graceActive) ...[
                    const SizedBox(width: 6),
                    const Tooltip(
                      message: 'Grace day active',
                      child: Text('⚡', style: TextStyle(fontSize: 14)),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              // Tree health bar
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: treeHealthScore / 100,
                        backgroundColor: Colors.white.withOpacity(0.25),
                        valueColor: AlwaysStoppedAnimation(
                          _healthColor(treeHealthScore),
                        ),
                        minHeight: 8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$treeHealthScore',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded, color: Colors.white54),
      ],
    );
  }

  Color _healthColor(int score) {
    if (score >= 75) return const Color(0xFF4CAF50);
    if (score >= 50) return const Color(0xFF8BC34A);
    if (score >= 25) return const Color(0xFFFFC107);
    return const Color(0xFFF44336);
  }
}

// ── Shared sprite placeholder (Rive in Sprint 4) ──────────────────────────────

class _SpritePlaceholder extends StatelessWidget {
  const _SpritePlaceholder({required this.emoji, required this.size});
  final String emoji;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(emoji, style: TextStyle(fontSize: size * 0.5)),
        ),
      );
}
