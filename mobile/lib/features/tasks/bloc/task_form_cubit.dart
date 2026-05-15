import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api/models/task_models.dart';
import '../data/task_repository.dart';

// ──────────────────────────────────────────────
// State
// ──────────────────────────────────────────────

sealed class TaskFormState extends Equatable {
  const TaskFormState();

  @override
  List<Object?> get props => [];
}

class TaskFormIdle extends TaskFormState {
  const TaskFormIdle();
}

class TaskFormLoading extends TaskFormState {
  const TaskFormLoading();
}

class TaskFormSuccess extends TaskFormState {
  const TaskFormSuccess(this.task);
  final Task task;

  @override
  List<Object?> get props => [task];
}

class TaskFormError extends TaskFormState {
  const TaskFormError(this.message, {this.isRRuleError = false});
  final String message;
  /// True when backend returned INVALID_RRULE — drives inline RRULE field error.
  final bool isRRuleError;

  @override
  List<Object?> get props => [message, isRRuleError];
}

// ──────────────────────────────────────────────
// Cubit
// ──────────────────────────────────────────────

/// Handles create and edit form submission including recurring task scope (M-036–M-037).
///
/// For recurring task edits, callers MUST set [scope] before calling [submitEdit].
/// Scope is passed as `?scope=` query param on PATCH/DELETE (CON-002 §3).
class TaskFormCubit extends Cubit<TaskFormState> {
  TaskFormCubit({required this.taskRepository}) : super(const TaskFormIdle());

  final TaskRepository taskRepository;

  /// The edit scope chosen via [RecurringEditScopeDialog].
  /// Null for new tasks or ONE_TIME tasks.
  RecurringEditScope? _scope;

  /// Set by the edit scope dialog (M-038) before navigating to the form.
  void setScope(RecurringEditScope scope) => _scope = scope;

  RecurringEditScope? get scope => _scope;

  // ── Create ─────────────────────────────────────────────────────────────────

  /// Validates and submits a CREATE request.
  /// When [request.taskType] == RECURRING, [request.rrule] must be non-null/non-empty.
  Future<void> submit(CreateTaskRequest request) async {
    if (!_validate(request.title, request.endAt, request.startAt)) return;
    if (!_validateRRule(request.taskType, request.rrule)) return;
    emit(const TaskFormLoading());
    try {
      final task = await taskRepository.createTask(request);
      emit(TaskFormSuccess(task));
    } on TaskRepositoryException catch (e) {
      emit(_mapRepoError(e));
    } catch (_) {
      emit(const TaskFormError('Failed to save task. Please try again.'));
    }
  }

  // ── Edit ───────────────────────────────────────────────────────────────────

  /// Validates and submits an EDIT request.
  /// For recurring task instances, [_scope] must be set first via [setScope].
  Future<void> submitEdit(String id, UpdateTaskRequest request) async {
    if (!_validate(request.title, request.endAt, request.startAt)) return;
    emit(const TaskFormLoading());
    try {
      final task = await taskRepository.updateTask(id, request, scope: _scope);
      emit(TaskFormSuccess(task));
    } on TaskRepositoryException catch (e) {
      emit(_mapRepoError(e));
    } catch (_) {
      emit(const TaskFormError('Failed to update task. Please try again.'));
    }
  }

  // ── Delete ─────────────────────────────────────────────────────────────────

  /// Delegates delete with scope to the repository.
  /// Callers on recurring tasks must call [setScope] first.
  Future<void> deleteTask(String id) async {
    emit(const TaskFormLoading());
    try {
      await taskRepository.deleteTask(id, scope: _scope);
      emit(TaskFormSuccess(_deletedTask));
    } on TaskRepositoryException catch (e) {
      emit(_mapRepoError(e));
    } catch (_) {
      emit(const TaskFormError('Failed to delete task. Please try again.'));
    }
  }

  void reset() => emit(const TaskFormIdle());

  // ── Validation ─────────────────────────────────────────────────────────────

  bool _validate(String? title, DateTime? endAt, DateTime? startAt) {
    if (title == null || title.trim().isEmpty) {
      emit(const TaskFormError('Title is required.'));
      return false;
    }
    if (title.length > 200) {
      emit(const TaskFormError('Title must be 200 characters or fewer.'));
      return false;
    }
    if (startAt != null && endAt != null && !endAt.isAfter(startAt)) {
      emit(const TaskFormError('End time must be after start time.'));
      return false;
    }
    return true;
  }

  bool _validateRRule(TaskType type, String? rrule) {
    if (type == TaskType.recurring &&
        (rrule == null || rrule.trim().isEmpty)) {
      emit(const TaskFormError(
        'Please select a recurrence schedule.',
        isRRuleError: true,
      ));
      return false;
    }
    return true;
  }

  TaskFormError _mapRepoError(TaskRepositoryException e) {
    if (e.message.contains('INVALID_RRULE') ||
        e.message.toLowerCase().contains('recurring rule')) {
      return TaskFormError(e.message, isRRuleError: true);
    }
    return TaskFormError(e.message);
  }
}

/// Sentinel "task" emitted on successful delete — avoids nullable TaskFormSuccess.
final _deletedTask = Task(
  id: '__deleted__',
  title: '',
  priority: TaskPriority.low,
  taskType: TaskType.oneTime,
  status: TaskStatus.cancelled,
  isOverdue: false,
  sortOrder: 0,
  isDetached: false,
  attachmentCount: 0,
  createdAt: _epoch,
  updatedAt: _epoch,
);

final _epoch = DateTime.utc(1970);
