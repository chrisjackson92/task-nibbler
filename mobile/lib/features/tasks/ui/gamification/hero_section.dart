import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../gamification/bloc/gamification_cubit.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';

/// Collapsible gamification hero section shown at the top of the task list
/// (BLU-004 §8, M-013).
///
/// Sprint 1–3: Static colour-block placeholder. Rive animations added in SPR-004-MB.
/// Tapping the hero navigates to [GamificationDetailScreen].
class HeroSection extends StatelessWidget {
  const HeroSection({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GamificationCubit, GamificationState>(
      builder: (context, state) => GestureDetector(
        onTap: () => context.push(AppRoutes.gamification),
        child: Container(
          margin: const EdgeInsets.all(16),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.heroGradientStart,
                AppColors.heroGradientEnd,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.seedGreen.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                // ── Sprite placeholder (Rive in Sprint 4) ─────────────────
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.eco_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
                const SizedBox(width: 16),

                // ── Stats column ───────────────────────────────────────────
                Expanded(
                  child: switch (state) {
                    GamificationWelcome() => _WelcomeContent(),
                    GamificationLoaded(:final streakCount,
                        :final treeHealthScore) =>
                      _LoadedContent(
                        streakCount: streakCount,
                        treeHealthScore: treeHealthScore,
                      ),
                  },
                ),

                // ── Chevron ────────────────────────────────────────────────
                const Icon(Icons.chevron_right, color: Colors.white54),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WelcomeContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Welcome! 🌱',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Complete your first task to start growing',
            style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13),
          ),
        ],
      );
}

class _LoadedContent extends StatelessWidget {
  const _LoadedContent({
    required this.streakCount,
    required this.treeHealthScore,
  });

  final int streakCount;
  final int treeHealthScore;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Streak ──────────────────────────────────────────────────────
          Row(
            children: [
              const Text('🔥', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 4),
              Text(
                '$streakCount day streak',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // ── Tree health bar ──────────────────────────────────────────────
          Row(
            children: [
              const Text('🌿', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 4),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: treeHealthScore / 100,
                    backgroundColor: Colors.white24,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.white),
                    minHeight: 8,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$treeHealthScore%',
                style:
                    const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        ],
      );
}
