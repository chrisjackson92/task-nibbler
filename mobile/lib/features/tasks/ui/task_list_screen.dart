import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/models/task_models.dart';
import '../../../core/connectivity/connectivity_cubit.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/offline_banner.dart';
import '../../../core/widgets/skeleton_loader.dart';
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
                              hasScrollBody: false,
                              child: TaskListSkeleton(),
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

// ── Enhanced empty state (M-055) ────────────────────────────────────────────

class _EmptyTasksView extends StatefulWidget {
  const _EmptyTasksView();

  @override
  State<_EmptyTasksView> createState() => _EmptyTasksViewState();
}

class _EmptyTasksViewState extends State<_EmptyTasksView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.05), // 20px ≈ 5% of typical screen
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: _EmptyTasksContent(),
      ),
    );
  }
}

class _EmptyTasksContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Clipboard illustration (CustomPaint)
            SizedBox(
              width: 100,
              height: 110,
              child: CustomPaint(
                key: const Key('empty_tasks_illustration'),
                painter: _ClipboardPainter(color: primary),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Nothing here yet',
              key: const Key('empty_tasks_headline'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap + to add your first task',
              key: const Key('empty_tasks_subtext'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('empty_tasks_add_button'),
              onPressed: () => context.push(AppRoutes.taskCreate),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Task'),
            ),
          ],
        ),
      ),
    );
  }
}

/// CustomPainter — clipboard with a checkmark, drawn in [color].
class _ClipboardPainter extends CustomPainter {
  const _ClipboardPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.15)
      ..style = PaintingStyle.fill;
    final outline = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Clipboard body
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(8, 20, size.width - 16, size.height - 24),
      const Radius.circular(10),
    );
    canvas.drawRRect(bodyRect, paint);
    canvas.drawRRect(bodyRect, outline..style = PaintingStyle.stroke);

    // Clipboard clip tab
    final clipRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width / 2 - 18, 12, 36, 20),
      const Radius.circular(6),
    );
    canvas.drawRRect(clipRect, Paint()..color = color.withOpacity(0.25));
    canvas.drawRRect(clipRect, outline);

    // Checkmark
    final checkPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final cx = size.width / 2;
    final cy = size.height / 2 + 12;
    final path = Path()
      ..moveTo(cx - 18, cy)
      ..lineTo(cx - 6, cy + 12)
      ..lineTo(cx + 18, cy - 14);
    canvas.drawPath(path, checkPaint);
  }

  @override
  bool shouldRepaint(_ClipboardPainter old) => old.color != color;
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
