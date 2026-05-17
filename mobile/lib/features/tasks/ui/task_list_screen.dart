import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/models/task_models.dart';
import '../../../core/connectivity/connectivity_cubit.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/offline_banner.dart';
import '../../gamification/bloc/gamification_cubit.dart';
import '../../gamification/ui/widgets/badge_award_listener.dart';
import '../bloc/task_list_bloc.dart';
import '../ui/gamification/hero_section.dart';
import 'widgets/filter_bottom_sheet.dart';
import 'widgets/task_tile.dart';

/// Home screen — task list with hero section (M-014, SPR-002-MB).
class TaskListScreen extends StatefulWidget {
  const TaskListScreen({super.key});

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> {
  @override
  void initState() {
    super.initState();
    context.read<TaskListBloc>().add(const LoadTasks());
    // Load real gamification state from API on app open (SPR-004-MB).
    context.read<GamificationCubit>().loadState();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BadgeAwardListener(
      child: BlocListener<ConnectivityCubit, ConnectivityStatus>(
        listener: (context, status) {
          if (status == ConnectivityStatus.connected) {
            context.read<TaskListBloc>().add(const RefreshTasks());
          }
        },
        child: Scaffold(
          body: Column(
            children: [
              const OfflineBanner(),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    // Subscribe BEFORE dispatching to avoid missing state transitions.
                    final completer = Completer<void>();
                    late StreamSubscription<TaskListState> sub;
                    sub = context.read<TaskListBloc>().stream.listen((state) {
                      if (state is TaskListLoaded || state is TaskListError) {
                        if (!completer.isCompleted) completer.complete();
                        sub.cancel();
                      }
                    });
                    context.read<TaskListBloc>().add(const RefreshTasks());
                    await completer.future;
                  },
                  child: CustomScrollView(
                  slivers: [
                    SliverAppBar(
                      floating: true,
                      snap: true,
                      title: const Text('My Tasks'),
                      actions: [
                        BlocBuilder<TaskListBloc, TaskListState>(
                          buildWhen: (prev, curr) =>
                              curr is TaskListLoaded || curr is TaskListLoading,
                          builder: (context, state) {
                            final filter = state is TaskListLoaded
                                ? state.activeFilter
                                : TaskFilter.empty;
                            return Stack(
                              children: [
                                IconButton(
                                  key: const Key('task_list_filter_button'),
                                  icon: const Icon(Icons.tune_rounded),
                                  onPressed: () => FilterBottomSheet.show(
                                    context,
                                    filter,
                                  ),
                                ),
                                if (filter.hasActiveFilter)
                                  Positioned(
                                    right: 8,
                                    top: 8,
                                    child: Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.settings_outlined),
                          onPressed: () => context.push(AppRoutes.settings),
                        ),
                      ],
                    ),
                    // Gamification hero (collapsible) — tap navigates to detail.
                    SliverToBoxAdapter(
                      child: GestureDetector(
                        key: const Key('hero_section_tap'),
                        onTap: () => context.push(AppRoutes.gamification),
                        child: const HeroSection(),
                      ),
                    ),
                    // Task list body.
                    BlocConsumer<TaskListBloc, TaskListState>(
                      listener: (context, state) {
                        if (state is TaskListError) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(state.message),
                              backgroundColor: theme.colorScheme.error,
                            ),
                          );
                        }
                      },
                      builder: (context, state) {
                        return switch (state) {
                          TaskListInitial() || TaskListLoading() =>
                            const SliverFillRemaining(
                              child: Center(child: CircularProgressIndicator()),
                            ),
                          TaskListError() => SliverFillRemaining(
                              child: _EmptyOrErrorView(
                                icon: Icons.error_outline_rounded,
                                message: state.message,
                                onRetry: () => context
                                    .read<TaskListBloc>()
                                    .add(const RefreshTasks()),
                              ),
                            ),
                          TaskListLoaded(tasks: final tasks) when tasks.isEmpty =>
                            const SliverFillRemaining(
                              child: _EmptyTasksView(),
                            ),
                          TaskListLoaded(
                            tasks: final tasks,
                            isOffline: final isOffline,
                          ) =>
                            _buildTaskList(context, tasks, isOffline),
                        };
                      },
                    ),
                  ],
                  ),
                ),
              ),
            ],
          ),
          floatingActionButton: BlocBuilder<TaskListBloc, TaskListState>(
            buildWhen: (p, c) => c is TaskListLoaded || c is TaskListInitial,
            builder: (context, state) {
              final isOffline = state is TaskListLoaded && state.isOffline;
              return Tooltip(
                message: isOffline ? "You're offline" : 'New task',
                child: FloatingActionButton(
                  key: const Key('task_list_fab'),
                  onPressed: isOffline
                      ? null
                      : () => context.push(AppRoutes.taskCreate),
                  child: Icon(
                    Icons.add_rounded,
                    color: isOffline ? Colors.grey : null,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTaskList(
    BuildContext context,
    List<Task> tasks,
    bool isOffline,
  ) {
    return SliverPadding(
      padding: const EdgeInsets.only(bottom: 80),
      sliver: SliverReorderableList(
        itemCount: tasks.length,
        onReorder: isOffline
            ? (_, __) {} // No-op when offline
            : (oldIndex, newIndex) {
                if (newIndex > oldIndex) newIndex--;
                context.read<TaskListBloc>().add(
                      ReorderTask(
                        taskId: tasks[oldIndex].id,
                        newSortOrder: newIndex,
                      ),
                    );
              },
        itemBuilder: (context, index) => ReorderableDragStartListener(
          key: ValueKey(tasks[index].id),
          index: index,
          enabled: !isOffline,
          child: TaskTile(task: tasks[index]),
        ),
      ),
    );
  }
}

// ── Empty / error views ───────────────────────────────────────────────────────

class _EmptyTasksView extends StatelessWidget {
  const _EmptyTasksView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_box_outline_blank_rounded,
            size: 64,
            color: theme.colorScheme.outline,
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
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyOrErrorView extends StatelessWidget {
  const _EmptyOrErrorView({
    required this.icon,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
