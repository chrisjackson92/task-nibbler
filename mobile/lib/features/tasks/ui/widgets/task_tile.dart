import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/api/models/task_models.dart';
import '../../bloc/task_list_bloc.dart';

// Priority colour system
Color _priorityColor(TaskPriority p) => switch (p) {
      TaskPriority.low => const Color(0xFF6EBD8B),
      TaskPriority.medium => const Color(0xFFF5A623),
      TaskPriority.high => const Color(0xFFE8604C),
      TaskPriority.critical => const Color(0xFFB91C1C),
    };

final _dateFormat = DateFormat('MMM d, y • h:mm a');

/// A single task row in the task list.
///
/// Features:
/// - Left-border accent by priority colour
/// - Overdue chip (red) if `is_overdue: true` — per SPR-002-MB exit criterion
/// - Swipe-to-dismiss → cancel confirmation dialog
/// - Complete button (checkmark icon)
/// - Attachment count badge
class TaskTile extends StatelessWidget {
  const TaskTile({super.key, required this.task});

  final Task task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _priorityColor(task.priority);

    return Dismissible(
      key: ValueKey(task.id),
      direction: DismissDirection.endToStart,
      background: _buildDismissBackground(context),
      confirmDismiss: (_) => _confirmCancel(context),
      onDismissed: (_) => context.read<TaskListBloc>().add(CancelTask(task.id)),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: theme.colorScheme.outline.withOpacity(0.12)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.push('/tasks/${task.id}', extra: task),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border(
                left: BorderSide(color: color, width: 4),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildContent(context, theme)),
                  const SizedBox(width: 8),
                  _buildActions(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          task.title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            decoration: task.status == TaskStatus.completed
                ? TextDecoration.lineThrough
                : null,
            color: task.status == TaskStatus.completed
                ? theme.colorScheme.onSurface.withOpacity(0.45)
                : null,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (task.description != null && task.description!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            task.description!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            _StatusChip(task: task),
            if (task.endAt != null) _buildDateChip(context, theme),
            if (task.attachmentCount > 0) _buildAttachmentBadge(theme),
            // M-039: recurring task indicator
            if (task.recurringRuleId != null && !task.isDetached)
              _RecurringChip(),
          ],
        ),
      ],
    );
  }

  /// Red chip when overdue (key: 'task_tile_overdue_chip'), plain text otherwise.
  Widget _buildDateChip(BuildContext context, ThemeData theme) {
    if (task.isOverdue) {
      return Chip(
        key: const Key('task_tile_overdue_chip'),
        label: Text(_dateFormat.format(task.endAt!.toLocal())),
        backgroundColor: Colors.red.shade50,
        labelStyle: TextStyle(
          color: Colors.red.shade800,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        avatar: Icon(Icons.warning_amber_rounded, size: 14, color: Colors.red.shade700),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: EdgeInsets.zero,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.schedule_outlined, size: 12, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 3),
        Text(
          _dateFormat.format(task.endAt!.toLocal()),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildAttachmentBadge(ThemeData theme) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.attach_file_rounded, size: 12, color: theme.colorScheme.primary),
          Text(
            '${task.attachmentCount}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
              fontSize: 11,
            ),
          ),
        ],
      );

  Widget _buildActions(BuildContext context) {
    // Only show complete button for pending tasks.
    if (task.status != TaskStatus.pending) return const SizedBox.shrink();

    final isOffline = context.select<TaskListBloc, bool>(
      (b) => b.state is TaskListLoaded && (b.state as TaskListLoaded).isOffline,
    );

    return Tooltip(
      message: isOffline ? 'Unavailable offline' : 'Mark complete',
      child: IconButton(
        key: Key('task_tile_complete_${task.id}'),
        icon: Icon(
          Icons.check_circle_outline_rounded,
          color: isOffline
              ? Theme.of(context).colorScheme.outline
              : const Color(0xFF6EBD8B),
        ),
        onPressed: isOffline
            ? null
            : () => context.read<TaskListBloc>().add(CompleteTask(task.id)),
      ),
    );
  }

  Widget _buildDismissBackground(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cancel_outlined, color: Colors.white),
            Text(
              'Cancel',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      );

  Future<bool> _confirmCancel(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Task?'),
        content: Text(
          'Cancel "${task.title}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cancel Task'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

// ── Status chip ──────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (task.status) {
      TaskStatus.pending => (
          'Pending',
          Theme.of(context).colorScheme.surfaceContainerHighest,
          Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      TaskStatus.completed => (
          'Done',
          const Color(0xFFE8F5E9),
          const Color(0xFF2E7D32),
        ),
      TaskStatus.cancelled => (
          'Cancelled',
          const Color(0xFFEFEFEF),
          const Color(0xFF6B6B6B),
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ── Recurring chip ────────────────────────────────────────────────────────────

/// Small 🔁 chip shown on recurring task instances in the list (M-039).
/// Not shown when `is_detached=true` (the instance was edited independently).
class _RecurringChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('task_tile_recurring_chip'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '🔁',
            style: TextStyle(fontSize: 10),
          ),
          const SizedBox(width: 3),
          Text(
            'Recurring',
            style: TextStyle(
              color: theme.colorScheme.onSecondaryContainer,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
