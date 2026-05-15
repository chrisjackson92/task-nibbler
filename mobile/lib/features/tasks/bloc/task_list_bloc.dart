import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api/models/task_models.dart';
import '../../../core/cache/task_cache.dart';
import '../../../core/connectivity/connectivity_cubit.dart';
import '../../gamification/bloc/gamification_cubit.dart';
import '../data/task_repository.dart';

// ──────────────────────────────────────────────
// Events
// ──────────────────────────────────────────────

sealed class TaskListEvent extends Equatable {
  const TaskListEvent();

  @override
  List<Object?> get props => [];
}

class LoadTasks extends TaskListEvent {
  const LoadTasks({this.filter = TaskFilter.empty});
  final TaskFilter filter;

  @override
  List<Object?> get props => [filter];
}

class RefreshTasks extends TaskListEvent {
  const RefreshTasks();
}

class FilterTasks extends TaskListEvent {
  const FilterTasks(this.filter);
  final TaskFilter filter;

  @override
  List<Object?> get props => [filter];
}

class ReorderTask extends TaskListEvent {
  const ReorderTask({required this.taskId, required this.newSortOrder});
  final String taskId;
  final int newSortOrder;

  @override
  List<Object?> get props => [taskId, newSortOrder];
}

class CompleteTask extends TaskListEvent {
  const CompleteTask(this.taskId);
  final String taskId;

  @override
  List<Object?> get props => [taskId];
}

class CancelTask extends TaskListEvent {
  const CancelTask(this.taskId);
  final String taskId;

  @override
  List<Object?> get props => [taskId];
}

class DeleteTask extends TaskListEvent {
  const DeleteTask(this.taskId);
  final String taskId;

  @override
  List<Object?> get props => [taskId];
}

// ──────────────────────────────────────────────
// States
// ──────────────────────────────────────────────

sealed class TaskListState extends Equatable {
  const TaskListState();

  @override
  List<Object?> get props => [];
}

class TaskListInitial extends TaskListState {
  const TaskListInitial();
}

class TaskListLoading extends TaskListState {
  const TaskListLoading();
}

class TaskListLoaded extends TaskListState {
  const TaskListLoaded({
    required this.tasks,
    required this.activeFilter,
    required this.isOffline,
  });

  final List<Task> tasks;
  final TaskFilter activeFilter;

  /// True when data comes from Hive (no network). Write operations disabled.
  final bool isOffline;

  TaskListLoaded copyWith({
    List<Task>? tasks,
    TaskFilter? activeFilter,
    bool? isOffline,
  }) =>
      TaskListLoaded(
        tasks: tasks ?? this.tasks,
        activeFilter: activeFilter ?? this.activeFilter,
        isOffline: isOffline ?? this.isOffline,
      );

  @override
  List<Object?> get props => [tasks, activeFilter, isOffline];
}

class TaskListError extends TaskListState {
  const TaskListError(this.message);
  final String message;

  @override
  List<Object?> get props => [message];
}

// ──────────────────────────────────────────────
// BLoC
// ──────────────────────────────────────────────

/// Manages the task list — load, filter, sort, complete, cancel, reorder.
///
/// Uses BLoC (not Cubit) because multiple complex, parallel event paths
/// each require distinct logic (BLU-004 §6 BLoC/Cubit decision matrix).
class TaskListBloc extends Bloc<TaskListEvent, TaskListState> {
  TaskListBloc({
    required this.taskRepository,
    required this.taskCache,
    required this.connectivityCubit,
    required this.gamificationCubit,
  }) : super(const TaskListInitial()) {
    on<LoadTasks>(_onLoad);
    on<RefreshTasks>(_onRefresh);
    on<FilterTasks>(_onFilter);
    on<ReorderTask>(_onReorder);
    on<CompleteTask>(_onComplete);
    on<CancelTask>(_onCancel);
    on<DeleteTask>(_onDelete);
  }

  final TaskRepository taskRepository;
  final TaskCache taskCache;
  final ConnectivityCubit connectivityCubit;
  final GamificationCubit gamificationCubit;

  // ── Handlers ───────────────────────────────────────────────────────────────

  Future<void> _onLoad(LoadTasks event, Emitter<TaskListState> emit) async {
    emit(const TaskListLoading());
    await _fetchTasks(event.filter, emit);
  }

  Future<void> _onRefresh(
    RefreshTasks event,
    Emitter<TaskListState> emit,
  ) async {
    final current = state;
    final filter = current is TaskListLoaded
        ? current.activeFilter
        : TaskFilter.empty;
    await _fetchTasks(filter, emit);
  }

  Future<void> _onFilter(
    FilterTasks event,
    Emitter<TaskListState> emit,
  ) async {
    emit(const TaskListLoading());
    await _fetchTasks(event.filter, emit);
  }

  Future<void> _onReorder(
    ReorderTask event,
    Emitter<TaskListState> emit,
  ) async {
    if (state is! TaskListLoaded) return;
    final loaded = state as TaskListLoaded;

    // Optimistic UI: reorder in-place immediately.
    final updated = List<Task>.from(loaded.tasks);
    final idx = updated.indexWhere((t) => t.id == event.taskId);
    if (idx == -1) return;

    final task = updated.removeAt(idx);
    updated.insert(
      event.newSortOrder.clamp(0, updated.length),
      task.copyWith(sortOrder: event.newSortOrder),
    );
    emit(loaded.copyWith(tasks: updated));

    // Persist to API (best-effort; don't revert on failure for now).
    if (!loaded.isOffline) {
      try {
        await taskRepository.updateSortOrder(event.taskId, event.newSortOrder);
      } catch (_) {
        // Silent — next full refresh will correct ordering from server.
      }
    }
  }

  Future<void> _onComplete(
    CompleteTask event,
    Emitter<TaskListState> emit,
  ) async {
    if (state is! TaskListLoaded) return;
    final loaded = state as TaskListLoaded;
    if (loaded.isOffline) return;

    try {
      final result = await taskRepository.completeTask(event.taskId);

      // Propagate delta to GamificationCubit — hero section rebuilds.
      gamificationCubit.applyDelta(result.gamificationDelta);

      // Replace the task in the list with the updated version.
      final updatedTasks = loaded.tasks
          .map((t) => t.id == event.taskId ? result.task : t)
          .toList();

      emit(loaded.copyWith(tasks: updatedTasks));
    } on TaskRepositoryException catch (e) {
      emit(TaskListError(e.message));
    } catch (e) {
      emit(const TaskListError('Failed to complete task.'));
    }
  }

  Future<void> _onCancel(
    CancelTask event,
    Emitter<TaskListState> emit,
  ) async {
    if (state is! TaskListLoaded) return;
    final loaded = state as TaskListLoaded;
    if (loaded.isOffline) return;

    try {
      final updated = await taskRepository.updateTask(
        event.taskId,
        const UpdateTaskRequest(status: TaskStatus.cancelled),
      );
      final updatedTasks = loaded.tasks
          .map((t) => t.id == event.taskId ? updated : t)
          .toList();
      emit(loaded.copyWith(tasks: updatedTasks));
    } on TaskRepositoryException catch (e) {
      emit(TaskListError(e.message));
    } catch (e) {
      emit(const TaskListError('Failed to cancel task.'));
    }
  }

  Future<void> _onDelete(
    DeleteTask event,
    Emitter<TaskListState> emit,
  ) async {
    if (state is! TaskListLoaded) return;
    final loaded = state as TaskListLoaded;
    if (loaded.isOffline) return;

    try {
      await taskRepository.deleteTask(event.taskId);
      final updatedTasks = loaded.tasks.where((t) => t.id != event.taskId).toList();
      emit(loaded.copyWith(tasks: updatedTasks));
    } on TaskRepositoryException catch (e) {
      emit(TaskListError(e.message));
    } catch (e) {
      emit(const TaskListError('Failed to delete task.'));
    }
  }

  // ── Shared helpers ─────────────────────────────────────────────────────────

  Future<void> _fetchTasks(
    TaskFilter filter,
    Emitter<TaskListState> emit,
  ) async {
    final isOffline =
        connectivityCubit.state == ConnectivityStatus.disconnected;

    if (isOffline) {
      // Offline path: load from Hive and apply filter client-side.
      try {
        final cached = await taskCache.loadTasks();
        final filtered = _applyFilterLocally(cached, filter);
        emit(TaskListLoaded(
          tasks: filtered,
          activeFilter: filter,
          isOffline: true,
        ));
      } catch (_) {
        emit(const TaskListError('Unable to load offline tasks.'));
      }
      return;
    }

    // Online path: fetch from API.
    try {
      final response = await taskRepository.getTasks(filter);
      emit(TaskListLoaded(
        tasks: response.data,
        activeFilter: filter,
        isOffline: false,
      ));
    } on TaskRepositoryException catch (e) {
      emit(TaskListError(e.message));
    } catch (e) {
      emit(const TaskListError('Failed to load tasks.'));
    }
  }

  /// Filters the cached task list locally when offline.
  /// This mirrors the server-side filtering for status and priority.
  List<Task> _applyFilterLocally(List<Task> tasks, TaskFilter filter) {
    return tasks.where((t) {
      // Status filter — including calculated overdue.
      if (filter.status != FilterStatus.all) {
        if (filter.status == FilterStatus.overdue) {
          if (!t.isOverdue) return false;
        } else {
          final targetStatus = TaskStatus.values.firstWhere(
            (s) => s.value.toLowerCase() == filter.status.value,
            orElse: () => TaskStatus.pending,
          );
          if (t.status != targetStatus) return false;
        }
      }

      // Priority filter.
      if (filter.priority != FilterPriority.all) {
        final targetPriority = TaskPriority.values.firstWhere(
          (p) => p.value.toLowerCase() == filter.priority.value,
          orElse: () => TaskPriority.medium,
        );
        if (t.priority != targetPriority) return false;
      }

      // Type filter.
      if (filter.type != FilterType.all) {
        final targetType = TaskType.values.firstWhere(
          (ty) => ty.value.toLowerCase() == filter.type.value.replaceAll('_', ''),
          orElse: () => TaskType.oneTime,
        );
        if (t.taskType != targetType) return false;
      }

      return true;
    }).toList();
  }
}
