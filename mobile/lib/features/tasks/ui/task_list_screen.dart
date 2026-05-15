import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/widgets/offline_banner.dart';
import 'gamification/hero_section.dart';

/// Home screen — gamification hero + task list (M-013, BLU-004 §8).
/// Sprint 1: task list is an empty placeholder. Tasks are implemented in SPR-002-MB.
class TaskListScreen extends StatelessWidget {
  const TaskListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Tasks'),
        actions: [
          IconButton(
            key: const Key('settings_nav_button'),
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push(AppRoutes.settings),
          ),
        ],
      ),
      body: OfflineBanner(
        child: CustomScrollView(
          slivers: [
            // ── Gamification hero ──────────────────────────────────────────
            const SliverToBoxAdapter(child: HeroSection()),

            // ── Task list placeholder (Sprint 2) ───────────────────────────
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.task_alt_rounded,
                      size: 72,
                      color: theme.colorScheme.outlineVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No tasks yet',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap + to add your first task',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new_task_fab'),
        onPressed: () {
          // Sprint 2: context.push(AppRoutes.newTask)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Task creation coming in Sprint 2')),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('New Task'),
      ),
    );
  }
}
