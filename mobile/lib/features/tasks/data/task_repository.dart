import 'package:dio/dio.dart';

import '../../../core/api/models/task_models.dart';
import '../../../core/auth/token_storage.dart';
import '../../../core/cache/task_cache.dart';

/// Repository wrapping all task API routes (CON-002 §3).
///
/// Every method returns typed models — never raw [Response] or [dynamic].
/// On successful list loads, results are written to Hive via [TaskCache].
class TaskRepository {
  const TaskRepository({
    required this.dio,
    required this.taskCache,
    required this.tokenStorage,
  });

  final Dio dio;
  final TaskCache taskCache;
  final TokenStorage tokenStorage;

  static const _basePath = '/api/v1/tasks';

  // ── Read ───────────────────────────────────────────────────────────────────

  /// GET /tasks — list with filter/sort/pagination params.
  /// Writes result to Hive on success so offline reads are fresh.
  Future<TaskListResponse> getTasks(TaskFilter filter) async {
    try {
      final response = await dio.get<Map<String, dynamic>>(
        _basePath,
        queryParameters: filter.toQueryParams(),
      );
      final result = TaskListResponse.fromJson(response.data!);
      // Persist to cache for offline fallback.
      await taskCache.saveTasks(result.data);
      return result;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// GET /tasks/:id — single task detail.
  Future<Task> getTask(String id) async {
    try {
      final response = await dio.get<Map<String, dynamic>>('$_basePath/$id');
      return Task.fromJson(response.data!);
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// Reads task list from Hive — called when [ConnectivityStatus.disconnected].
  Future<List<Task>> getTasksOffline() => taskCache.loadTasks();

  // ── Write ──────────────────────────────────────────────────────────────────

  /// POST /tasks — create a new task.
  Future<Task> createTask(CreateTaskRequest request) async {
    try {
      final response = await dio.post<Map<String, dynamic>>(
        _basePath,
        data: request.toJson(),
      );
      return Task.fromJson(response.data!);
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// PATCH /tasks/:id — partial update.
  /// [scope] is required when updating a recurring task instance (CON-002 §3).
  Future<Task> updateTask(
    String id,
    UpdateTaskRequest request, {
    RecurringEditScope? scope,
  }) async {
    try {
      final response = await dio.patch<Map<String, dynamic>>(
        '$_basePath/$id',
        queryParameters: scope != null ? {'scope': scope.toApiParam()} : null,
        data: request.toJson(),
      );
      return Task.fromJson(response.data!);
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// DELETE /tasks/:id — remove task.
  /// [scope] is required when deleting a recurring task instance (CON-002 §3).
  Future<void> deleteTask(String id, {RecurringEditScope? scope}) async {
    try {
      await dio.delete<void>(
        '$_basePath/$id',
        queryParameters: scope != null ? {'scope': scope.toApiParam()} : null,
      );
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// POST /tasks/:id/complete — mark task complete.
  /// Returns the updated task + gamification delta (CON-002 §3).
  Future<CompleteTaskResponse> completeTask(String id) async {
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '$_basePath/$id/complete',
      );
      return CompleteTaskResponse.fromJson(response.data!);
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// PATCH /tasks/:id/sort-order — update display order.
  Future<void> updateSortOrder(String id, int sortOrder) async {
    try {
      await dio.patch<void>(
        '$_basePath/$id/sort-order',
        data: SortOrderRequest(sortOrder: sortOrder).toJson(),
      );
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  // ── Error mapping ──────────────────────────────────────────────────────────

  /// Maps DioException → user-readable message using CON-001 §5 error codes.
  Exception _mapError(DioException e) {
    String? code;
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      final err = data['error'] as Map<String, dynamic>? ?? data;
      code = err['code'] as String?;
    }
    return switch (code) {
      'TASK_NOT_FOUND' => const TaskRepositoryException('Task not found.'),
      'VALIDATION_ERROR' => const TaskRepositoryException(
          'Please check your input and try again.',
        ),
      'INVALID_RRULE' => const TaskRepositoryException(
          'The recurring rule is invalid.',
        ),
      'INVALID_DATE_RANGE' => const TaskRepositoryException(
          'End time must be after start time.',
        ),
      _ when e.response?.statusCode == 401 => const TaskRepositoryException(
          'Session expired. Please log in again.',
        ),
      _ when e.response?.statusCode == 409 => const TaskRepositoryException(
          'This task has already been completed or cancelled.',
        ),
      _ =>
        TaskRepositoryException(e.message ?? 'An unexpected error occurred.'),
    };
  }
}

/// Typed exception from [TaskRepository].
class TaskRepositoryException implements Exception {
  const TaskRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
}
