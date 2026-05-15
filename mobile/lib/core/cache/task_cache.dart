import 'package:hive_flutter/hive_flutter.dart';

/// Box name constant — never use bare strings in feature code.
const kTaskBoxName = 'tasks_box';

/// Hive wrapper for offline task list caching (BLU-004 §5, GOV-011 §5).
///
/// Tasks are stored as raw JSON maps (no type adapter needed for Sprint 1).
/// Type adapters + [GamificationStateHiveModel] will be added in Sprint 2+.
class TaskCache {
  const TaskCache();

  /// Overwrites the cached task list with [tasks] (raw JSON maps).
  Future<void> saveTasks(List<Map<String, dynamic>> tasks) async {
    final box = await Hive.openBox<dynamic>(kTaskBoxName);
    await box.clear();
    for (var i = 0; i < tasks.length; i++) {
      await box.put(i, tasks[i]);
    }
  }

  /// Returns all cached tasks as raw JSON maps.
  Future<List<Map<String, dynamic>>> loadTasks() async {
    final box = await Hive.openBox<dynamic>(kTaskBoxName);
    return box.values
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Clears the task cache — called on logout and account deletion (GOV-011 §5.4).
  Future<void> clear() async {
    final box = await Hive.openBox<dynamic>(kTaskBoxName);
    await box.clear();
  }
}
