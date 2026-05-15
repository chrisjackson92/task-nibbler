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
  const TaskFormError(this.message);
  final String message;

  @override
  List<Object?> get props => [message];
}

// ──────────────────────────────────────────────
// Cubit
// ──────────────────────────────────────────────

/// Handles both create and edit task form submission (BLU-004 §6 Cubit rule:
/// single linear flow → Cubit; complex multi-branch → BLoC).
class TaskFormCubit extends Cubit<TaskFormState> {
  TaskFormCubit({required this.taskRepository}) : super(const TaskFormIdle());

  final TaskRepository taskRepository;

  /// Validates and submits a CREATE request.
  Future<void> submit(CreateTaskRequest request) async {
    if (!_validate(request.title, request.endAt, request.startAt)) return;
    emit(const TaskFormLoading());
    try {
      final task = await taskRepository.createTask(request);
      emit(TaskFormSuccess(task));
    } on TaskRepositoryException catch (e) {
      emit(TaskFormError(e.message));
    } catch (_) {
      emit(const TaskFormError('Failed to save task. Please try again.'));
    }
  }

  /// Validates and submits an EDIT/UPDATE request.
  Future<void> submitEdit(String id, UpdateTaskRequest request) async {
    if (!_validate(
      request.title,
      request.endAt,
      request.startAt,
    )) return;
    emit(const TaskFormLoading());
    try {
      final task = await taskRepository.updateTask(id, request);
      emit(TaskFormSuccess(task));
    } on TaskRepositoryException catch (e) {
      emit(TaskFormError(e.message));
    } catch (_) {
      emit(const TaskFormError('Failed to update task. Please try again.'));
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
}
