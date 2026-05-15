import 'package:hive_flutter/hive_flutter.dart';

import '../api/models/task_models.dart';

/// Box name constant — never use bare strings in feature code.
const kTaskBoxName = 'tasks_box';

/// Hive wrapper for offline task list caching (BLU-004 §5, GOV-011 §5).
///
/// Tasks are stored as raw JSON maps (no Hive type adapter needed until
/// Sprint 4 when typed adapters offer a measurable perf win).
class TaskCache {
  const TaskCache();

  // ── Write ──────────────────────────────────────────────────────────────────

  /// Overwrites the full cached task list with [tasks].
  Future<void> saveTasks(List<Task> tasks) async {
    final box = await Hive.openBox<dynamic>(kTaskBoxName);
    await box.clear();
    for (var i = 0; i < tasks.length; i++) {
      await box.put(i, tasks[i].toJson());
    }
  }

  /// Upserts a single task (by id key). Used after create/update/complete.
  Future<void> saveTask(Task task) async {
    final box = await Hive.openBox<dynamic>(kTaskBoxName);
    await box.put('task_${task.id}', task.toJson());
  }

  // ── Read ───────────────────────────────────────────────────────────────────

  /// Returns all cached tasks, sorted by [Task.sortOrder].
  Future<List<Task>> loadTasks() async {
    final box = await Hive.openBox<dynamic>(kTaskBoxName);
    final tasks = box.values
        .whereType<Map>()
        .map((e) => Task.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    tasks.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return tasks;
  }

  /// Returns a single cached task by id, or null if not found.
  Future<Task?> getTaskById(String id) async {
    final box = await Hive.openBox<dynamic>(kTaskBoxName);
    // Try the dedicated key first, then scan list entries.
    final direct = box.get('task_$id');
    if (direct is Map) {
      return Task.fromJson(Map<String, dynamic>.from(direct));
    }
    // Fall back — scan values written by saveTasks
    for (final v in box.values) {
      if (v is Map && v['id'] == id) {
        return Task.fromJson(Map<String, dynamic>.from(v));
      }
    }
    return null;
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Clears the task cache — called on logout and account deletion (GOV-011 §5.4).
  Future<void> clear() async {
    final box = await Hive.openBox<dynamic>(kTaskBoxName);
    await box.clear();
  }
}
