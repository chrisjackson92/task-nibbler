import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api/models/gamification_models.dart';
import '../../../core/theme/app_colors.dart';
import '../bloc/gamification_cubit.dart';
import '../ui/widgets/badge_shelf_widget.dart';
import '../ui/widgets/sprite_widget.dart';
import '../ui/widgets/tree_widget.dart';

/// Full-screen gamification detail — shows sprite, tree, stats, and badge shelf (M-030).
/// Navigated to by tapping the hero section in the task list.
class GamificationDetailScreen extends StatelessWidget {
  const GamificationDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocBuilder<GamificationCubit, GamificationState>(
        builder: (context, state) => switch (state) {
          GamificationInitial() => _buildLoading(),
          GamificationLoading() => _buildLoading(),
          GamificationLoaded(gamState: final g, badges: final b) =>
            _buildContent(context, g, b),
          GamificationBadgeAwarded(gamState: final g, badges: final b) =>
            _buildContent(context, g, b),
          GamificationError(message: final msg) => _buildError(context, msg),
        },
      ),
    );
  }

  Widget _buildLoading() => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );

  Widget _buildError(BuildContext context, String msg) => Scaffold(
        appBar: AppBar(title: const Text('Your Progress')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(msg),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () =>
                    context.read<GamificationCubit>().loadState(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );

  Widget _buildContent(
    BuildContext context,
    GamificationStateData gamState,
    List<BadgeData> badges,
  ) {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 120,
          pinned: true,
          flexibleSpace: FlexibleSpaceBar(
            title: const Text(
              'Your Progress',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            background: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.heroGradientStart,
                    AppColors.heroGradientEnd,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sprite + Tree side by side
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 160,
                        child: gamState.spriteType == 'sprite_b'
                            ? SpriteBWidget(healthScore: gamState.treeHealthScore, size: 140)
                            : SpriteAWidget(healthScore: gamState.treeHealthScore, size: 140),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: SizedBox(
                        height: 160,
                        child: gamState.treeType == 'tree_b'
                            ? TreeBWidget(healthScore: gamState.treeHealthScore, size: 140)
                            : TreeAWidget(healthScore: gamState.treeHealthScore, size: 140),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Stats row
                _StatsRow(gamState: gamState),
                const SizedBox(height: 24),

                // WELCOME message
                if (gamState.spriteState == SpriteState.welcome) ...[
                  _WelcomeCard(),
                  const SizedBox(height: 24),
                ],

                // Grace day notice
                if (gamState.graceActive) ...[
                  _GraceCard(),
                  const SizedBox(height: 24),
                ],

                // Badge shelf (all 14 badges)
                BadgeShelfWidget(badges: badges),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Stats row ─────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.gamState});
  final GamificationStateData gamState;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            key: const Key('detail_streak_count'),
            icon: '🔥',
            label: 'Day Streak',
            value: '${gamState.streakCount}',
            subtitle: gamState.graceActive ? '⚡ Grace' : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            key: const Key('detail_tree_health'),
            icon: '🌿',
            label: 'Tree Health',
            value: '${gamState.treeHealthScore}',
            subtitle: '/ 100',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            key: const Key('detail_badges_count'),
            icon: '🏅',
            label: 'Badges',
            value: '${gamState.totalBadgesEarned}',
            subtitle: '/ 14',
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
  });

  final String icon;
  final String label;
  final String value;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          Text(label,
              style: theme.textTheme.labelSmall,
              textAlign: TextAlign.center),
          if (subtitle != null)
            Text(subtitle!,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.outline)),
        ],
      ),
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.heroGradientEnd.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: AppColors.heroGradientEnd.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Text('🌱', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Complete your first task to start your streak and begin growing your tree!',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _GraceCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFD600).withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFD600).withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bolt_rounded,
              color: Color(0xFFFFD600), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Grace day active — your streak is protected for today.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
