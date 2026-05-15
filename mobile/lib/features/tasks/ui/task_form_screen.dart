import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/models/task_models.dart';
import '../../../core/widgets/loading_overlay.dart';
import '../bloc/task_form_cubit.dart';
import '../bloc/task_list_bloc.dart';

/// Create/Edit task form screen (M-017).
///
/// When [existingTask] is null, runs in CREATE mode.
/// When [existingTask] is provided, runs in EDIT mode.
class TaskFormScreen extends StatefulWidget {
  const TaskFormScreen({super.key, this.existingTask});

  final Task? existingTask;

  bool get isEditMode => existingTask != null;

  @override
  State<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends State<TaskFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _addressCtrl;
  late TaskPriority _priority;
  late TaskType _taskType;
  DateTime? _startAt;
  DateTime? _endAt;

  @override
  void initState() {
    super.initState();
    final t = widget.existingTask;
    _titleCtrl = TextEditingController(text: t?.title ?? '');
    _descCtrl = TextEditingController(text: t?.description ?? '');
    _addressCtrl = TextEditingController(text: t?.address ?? '');
    _priority = t?.priority ?? TaskPriority.medium;
    _taskType = t?.taskType ?? TaskType.oneTime;
    _startAt = t?.startAt;
    _endAt = t?.endAt;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocConsumer<TaskFormCubit, TaskFormState>(
      listener: (context, state) {
        if (state is TaskFormSuccess) {
          // Refresh task list after save.
          context.read<TaskListBloc>().add(const RefreshTasks());
          context.pop();
        } else if (state is TaskFormError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: theme.colorScheme.error,
            ),
          );
        }
      },
      builder: (context, state) {
        final isLoading = state is TaskFormLoading;
        return LoadingOverlay(
          isLoading: isLoading,
          child: Scaffold(
            appBar: AppBar(
              title: Text(widget.isEditMode ? 'Edit Task' : 'New Task'),
              actions: [
                TextButton(
                  key: const Key('task_form_save_button'),
                  onPressed: isLoading ? null : _submit,
                  child: const Text('Save'),
                ),
              ],
            ),
            body: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Title (required)
                  TextFormField(
                    key: const Key('task_form_title_field'),
                    controller: _titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Title *',
                      hintText: 'What needs to be done?',
                    ),
                    maxLength: 200,
                    textInputAction: TextInputAction.next,
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Title is required' : null,
                  ),
                  const SizedBox(height: 16),

                  // Description
                  TextFormField(
                    key: const Key('task_form_description_field'),
                    controller: _descCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      hintText: 'Add details...',
                    ),
                    maxLines: 3,
                    maxLength: 2000,
                  ),
                  const SizedBox(height: 16),

                  // Address
                  TextFormField(
                    key: const Key('task_form_address_field'),
                    controller: _addressCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Address',
                      hintText: '123 Main St...',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                    maxLength: 500,
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: 16),

                  // Priority (required)
                  Text('Priority *', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  _buildPrioritySelector(),
                  const SizedBox(height: 20),

                  // Task type (required)
                  Text('Type *', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  _buildTypeSelector(),

                  if (_taskType == TaskType.recurring) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer
                            .withOpacity(0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '📅 Recurring rule (RRULE) configuration will be available in Sprint 5.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),

                  // Date pickers
                  Text('Schedule', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  _DatePickerRow(
                    key: const Key('task_form_start_picker'),
                    label: 'Start',
                    value: _startAt,
                    onChanged: (dt) => setState(() => _startAt = dt),
                  ),
                  const SizedBox(height: 8),
                  _DatePickerRow(
                    key: const Key('task_form_end_picker'),
                    label: 'Due',
                    value: _endAt,
                    onChanged: (dt) => setState(() => _endAt = dt),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPrioritySelector() {
    return SegmentedButton<TaskPriority>(
      key: const Key('task_form_priority_selector'),
      segments: TaskPriority.values
          .map((p) => ButtonSegment<TaskPriority>(
                value: p,
                label: Text(p.label),
              ))
          .toList(),
      selected: {_priority},
      onSelectionChanged: (s) => setState(() => _priority = s.first),
    );
  }

  Widget _buildTypeSelector() {
    return SegmentedButton<TaskType>(
      key: const Key('task_form_type_selector'),
      segments: TaskType.values
          .map((t) => ButtonSegment<TaskType>(
                value: t,
                icon: Icon(
                  t == TaskType.recurring
                      ? Icons.repeat_rounded
                      : Icons.looks_one_outlined,
                  size: 16,
                ),
                label: Text(t.label),
              ))
          .toList(),
      selected: {_taskType},
      onSelectionChanged: (s) => setState(() => _taskType = s.first),
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final cubit = context.read<TaskFormCubit>();
    final title = _titleCtrl.text.trim();
    final description = _descCtrl.text.trim();
    final address = _addressCtrl.text.trim();

    if (widget.isEditMode) {
      cubit.submitEdit(
        widget.existingTask!.id,
        UpdateTaskRequest(
          title: title,
          description: description.isEmpty ? null : description,
          address: address.isEmpty ? null : address,
          priority: _priority,
          taskType: _taskType,
          startAt: _startAt,
          endAt: _endAt,
        ),
      );
    } else {
      cubit.submit(
        CreateTaskRequest(
          title: title,
          description: description.isEmpty ? null : description,
          address: address.isEmpty ? null : address,
          priority: _priority,
          taskType: _taskType,
          startAt: _startAt,
          endAt: _endAt,
        ),
      );
    }
  }
}

// ── Date picker row ───────────────────────────────────────────────────────────

class _DatePickerRow extends StatelessWidget {
  const _DatePickerRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final DateTime? value;
  final void Function(DateTime?) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final display = value != null
        ? DateFormat('MMM d, y • h:mm a').format(value!.toLocal())
        : 'Not set';

    return InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outline.withOpacity(0.5)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
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
                  Text(display, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
            if (value != null)
              IconButton(
                icon: const Icon(Icons.clear_rounded, size: 18),
                onPressed: () => onChanged(null),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final date = await showDatePicker(
      context: context,
      initialDate: value ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (date == null || !context.mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: value != null
          ? TimeOfDay.fromDateTime(value!)
          : TimeOfDay.now(),
    );
    if (time == null || !context.mounted) return;

    onChanged(DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    ));
  }
}
