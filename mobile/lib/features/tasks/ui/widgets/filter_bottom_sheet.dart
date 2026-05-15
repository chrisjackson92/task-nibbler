import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/api/models/task_models.dart';
import '../../bloc/task_list_bloc.dart';

/// Modal bottom sheet for filtering and sorting the task list (M-015).
///
/// Dispatches [FilterTasks] when the user taps "Apply".
class FilterBottomSheet extends StatefulWidget {
  const FilterBottomSheet({super.key, required this.currentFilter});

  final TaskFilter currentFilter;

  static Future<void> show(
    BuildContext context,
    TaskFilter currentFilter,
  ) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => BlocProvider.value(
          value: context.read<TaskListBloc>(),
          child: FilterBottomSheet(currentFilter: currentFilter),
        ),
      );

  @override
  State<FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<FilterBottomSheet> {
  late FilterStatus _status;
  late FilterPriority _priority;
  late FilterType _type;
  late SortField _sort;
  late String _order;

  @override
  void initState() {
    super.initState();
    _status = widget.currentFilter.status;
    _priority = widget.currentFilter.priority;
    _type = widget.currentFilter.type;
    _sort = widget.currentFilter.sort;
    _order = widget.currentFilter.order;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, controller) => Column(
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.outline.withOpacity(0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                Text('Filter & Sort',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                _sectionLabel(context, 'Status'),
                _buildChipGroup<FilterStatus>(
                  values: FilterStatus.values,
                  selected: _status,
                  label: (v) => v.label,
                  onSelected: (v) => setState(() => _status = v),
                ),
                const SizedBox(height: 16),
                _sectionLabel(context, 'Priority'),
                _buildChipGroup<FilterPriority>(
                  values: FilterPriority.values,
                  selected: _priority,
                  label: (v) => v.label,
                  onSelected: (v) => setState(() => _priority = v),
                ),
                const SizedBox(height: 16),
                _sectionLabel(context, 'Type'),
                _buildChipGroup<FilterType>(
                  values: FilterType.values,
                  selected: _type,
                  label: (v) => v.label,
                  onSelected: (v) => setState(() => _type = v),
                ),
                const SizedBox(height: 16),
                _sectionLabel(context, 'Sort By'),
                _buildChipGroup<SortField>(
                  values: SortField.values,
                  selected: _sort,
                  label: (v) => v.label,
                  onSelected: (v) => setState(() => _sort = v),
                ),
                const SizedBox(height: 16),
                _sectionLabel(context, 'Order'),
                Row(
                  children: [
                    _OrderChip(
                      label: 'Ascending',
                      icon: Icons.arrow_upward_rounded,
                      selected: _order == 'asc',
                      onTap: () => setState(() => _order = 'asc'),
                    ),
                    const SizedBox(width: 8),
                    _OrderChip(
                      label: 'Descending',
                      icon: Icons.arrow_downward_rounded,
                      selected: _order == 'desc',
                      onTap: () => setState(() => _order = 'desc'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
          _buildActions(context),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );

  Widget _buildChipGroup<T>({
    required List<T> values,
    required T selected,
    required String Function(T) label,
    required void Function(T) onSelected,
  }) =>
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: values
            .map(
              (v) => FilterChip(
                label: Text(label(v)),
                selected: v == selected,
                onSelected: (_) => onSelected(v),
              ),
            )
            .toList(),
      );

  Widget _buildActions(BuildContext context) {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 16 + safeBottom),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              key: const Key('filter_clear_button'),
              onPressed: () {
                setState(() {
                  _status = FilterStatus.all;
                  _priority = FilterPriority.all;
                  _type = FilterType.all;
                  _sort = SortField.sortOrder;
                  _order = 'asc';
                });
              },
              child: const Text('Clear All'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: FilledButton(
              key: const Key('filter_apply_button'),
              onPressed: () {
                context.read<TaskListBloc>().add(
                      FilterTasks(
                        TaskFilter(
                          status: _status,
                          priority: _priority,
                          type: _type,
                          sort: _sort,
                          order: _order,
                        ),
                      ),
                    );
                Navigator.of(context).pop();
              },
              child: const Text('Apply Filters'),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderChip extends StatelessWidget {
  const _OrderChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16,
                color: selected
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
