import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/models/task_models.dart';
import '../bloc/task_list_bloc.dart';

final _dateFormat = DateFormat('MMM d, y • h:mm a');

/// Full task detail view (M-016).
///
/// Shows all task fields. `is_overdue: true` renders a red date chip.
/// Attachment count is shown (tappable in SPR-003-MB).
class TaskDetailScreen extends StatelessWidget {
  const TaskDetailScreen({super.key, required this.task});

  final Task task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOffline = context.select<TaskListBloc, bool>(
      (b) => b.state is TaskListLoaded && (b.state as TaskListLoaded).isOffline,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Task Detail'),
        actions: [
          if (!isOffline)
            IconButton(
              key: const Key('task_detail_edit_button'),
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => context.push('/tasks/${task.id}/edit', extra: task),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Title + priority badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  task.title,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              _PriorityBadge(priority: task.priority),
            ],
          ),
          const SizedBox(height: 12),

          // Status + type chips
          Wrap(
            spacing: 8,
            children: [
              _StatusBadge(status: task.status),
              _TypeBadge(type: task.taskType),
            ],
          ),
          const Divider(height: 32),

          // Description
          if (task.description != null && task.description!.isNotEmpty) ...[
            _DetailRow(
              icon: Icons.notes_rounded,
              label: 'Description',
              content: task.description!,
            ),
            const SizedBox(height: 16),
          ],

          // Address
          if (task.address != null && task.address!.isNotEmpty) ...[
            _DetailRow(
              icon: Icons.location_on_outlined,
              label: 'Address',
              content: task.address!,
            ),
            const SizedBox(height: 16),
          ],

          // Dates
          if (task.startAt != null)
            _DetailRow(
              icon: Icons.play_arrow_outlined,
              label: 'Starts',
              content: _dateFormat.format(task.startAt!.toLocal()),
            ),
          if (task.endAt != null) ...[
            const SizedBox(height: 12),
            _DueDateRow(task: task),
          ],

          if (task.completedAt != null) ...[
            const SizedBox(height: 12),
            _DetailRow(
              icon: Icons.check_circle_outline_rounded,
              label: 'Completed',
              content: _dateFormat.format(task.completedAt!.toLocal()),
            ),
          ],
          if (task.cancelledAt != null) ...[
            const SizedBox(height: 12),
            _DetailRow(
              icon: Icons.cancel_outlined,
              label: 'Cancelled',
              content: _dateFormat.format(task.cancelledAt!.toLocal()),
            ),
          ],

          const Divider(height: 32),

          // Attachments count (tappable in SPR-003-MB)
          _DetailRow(
            icon: Icons.attach_file_rounded,
            label: 'Attachments',
            content: '${task.attachmentCount} file${task.attachmentCount == 1 ? '' : 's'}',
            trailing: task.attachmentCount > 0
                ? const Icon(Icons.chevron_right_rounded)
                : null,
          ),

          const SizedBox(height: 24),
        ],
      ),
      // Complete button — only for pending, online tasks.
      bottomNavigationBar: task.status == TaskStatus.pending && !isOffline
          ? _CompleteBar(task: task)
          : null,
    );
  }
}

// ── Detail widgets ────────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.content,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String content;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 2),
              Text(content, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _DueDateRow extends StatelessWidget {
  const _DueDateRow({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context) {
    if (task.isOverdue) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded,
              size: 20, color: Colors.red.shade700),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DUE'.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.red.shade800,
                      letterSpacing: 0.8,
                    ),
              ),
              Chip(
                key: const Key('task_detail_overdue_chip'),
                label: Text(
                  '${_dateFormat.format(task.endAt!.toLocal())} — OVERDUE',
                ),
                backgroundColor: Colors.red.shade50,
                labelStyle: TextStyle(
                  color: Colors.red.shade800,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      );
    }

    return _DetailRow(
      icon: Icons.flag_outlined,
      label: 'Due',
      content: _dateFormat.format(task.endAt!.toLocal()),
    );
  }
}

class _CompleteBar extends StatelessWidget {
  const _CompleteBar({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton.icon(
          key: const Key('task_detail_complete_button'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: const Color(0xFF6EBD8B),
          ),
          icon: const Icon(Icons.check_rounded),
          label: const Text('Mark Complete'),
          onPressed: () {
            context.read<TaskListBloc>().add(CompleteTask(task.id));
            context.pop();
          },
        ),
      ),
    );
  }
}

// ── Badge widgets ─────────────────────────────────────────────────────────────

class _PriorityBadge extends StatelessWidget {
  const _PriorityBadge({required this.priority});
  final TaskPriority priority;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (priority) {
      TaskPriority.low => ('Low', const Color(0xFF6EBD8B)),
      TaskPriority.medium => ('Medium', const Color(0xFFF5A623)),
      TaskPriority.high => ('High', const Color(0xFFE8604C)),
      TaskPriority.critical => ('Critical', const Color(0xFFB91C1C)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final TaskStatus status;

  @override
  Widget build(BuildContext context) => Chip(
        label: Text(status.label),
        visualDensity: VisualDensity.compact,
      );
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});
  final TaskType type;

  @override
  Widget build(BuildContext context) => Chip(
        label: Text(type.label),
        avatar: Icon(
          type == TaskType.recurring
              ? Icons.repeat_rounded
              : Icons.looks_one_outlined,
          size: 14,
        ),
        visualDensity: VisualDensity.compact,
      );
}
