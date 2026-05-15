import 'package:flutter/material.dart';

import '../../../../core/api/models/task_models.dart';

/// Modal bottom sheet shown BEFORE navigating to the edit form for any
/// RECURRING task instance (M-038, SPR-005-MB §Architect Checklist).
///
/// Returns a [RecurringEditScope] or null if dismissed (caller should abort navigation).
///
/// Usage:
/// ```dart
/// final scope = await RecurringEditScopeDialog.show(context);
/// if (scope == null) return; // user cancelled — do not open form
/// ```
class RecurringEditScopeDialog {
  RecurringEditScopeDialog._();

  static Future<RecurringEditScope?> show(BuildContext context) {
    return showModalBottomSheet<RecurringEditScope>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _EditScopeSheet(),
    );
  }
}

class _EditScopeSheet extends StatelessWidget {
  const _EditScopeSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                key: const Key('scope_dialog_handle'),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Edit recurring task',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Which tasks would you like to update?',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 8),
            const Divider(),
            _ScopeOption(
              key: const Key('scope_this_only'),
              scope: RecurringEditScope.thisOnly,
              icon: Icons.event_outlined,
            ),
            const _ScopeOption(
              key: Key('scope_this_and_future'),
              scope: RecurringEditScope.thisAndFuture,
              icon: Icons.event_repeat_outlined,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _ScopeOption extends StatelessWidget {
  const _ScopeOption({
    super.key,
    required this.scope,
    required this.icon,
  });

  final RecurringEditScope scope;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(scope.label, style: theme.textTheme.bodyLarge),
      subtitle: Text(
        scope.subtitle,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.outline),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => Navigator.of(context).pop(scope),
    );
  }
}
