---
id: SPR-002-MB
title: "Sprint 2 — Task UI Mobile"
type: sprint
status: MERGED
assignee: coder
agent_boot: AGT-002-MB_Mobile_Developer_Agent.md
sprint_number: 2
track: mobile
estimated_days: 5
blocked_by: SPR-002-BE (task endpoints must be live on staging) + SPR-001-MB (must pass audit)
related: [BLU-004, CON-002, PRJ-001]
created: 2026-05-14
updated: 2026-05-14
---

> **BLUF:** Build the full task management UI — home screen with task list (filter/sort, drag-to-reorder), task detail, create/edit form, complete and cancel actions, overdue indicator, and offline read fallback from Hive cache.

# Sprint 2-MB — Task UI Mobile

---

## Pre-Conditions

- [ ] `SPR-001-MB` Architect audit PASSED
- [ ] `SPR-002-BE` complete — task endpoints live on staging
- [ ] Read `CON-002_API_Contract.md` §3 (Task routes) in full
- [ ] Read `PRJ-001` §4.2 (Core Daily Loop) and §5.2 (Task Entity) in full

---

## Exit Criteria

- [ ] Task list screen loads tasks from API and displays them
- [ ] Filter bottom sheet filters by status, priority, type; active filter shown as chip
- [ ] Sort controls work: by sort_order, due date, priority
- [ ] Drag-to-reorder updates `sort_order` via `PATCH /tasks/:id/sort-order`
- [ ] Task detail screen shows all fields; `is_overdue` shows red date chip
- [ ] Create/edit form validates required fields (title, priority); saves successfully
- [ ] Complete button calls `POST /tasks/:id/complete`; triggers hero section refresh
- [ ] Cancel action (swipe or menu): confirmation dialog → `PATCH status=CANCELLED`
- [ ] Offline: task list loads from Hive cache with "Offline (read-only)" indicator
- [ ] Offline: FAB and complete/cancel buttons are disabled with tooltip explanation
- [ ] `fvm flutter test` passes, ≥ 70% TaskListBloc + TaskDetailCubit coverage

---

## Task List

| BCK ID | Task | Notes |
|:-------|:-----|:------|
| M-014 | Task list screen (TaskListBloc: load, filter, sort) | Reads from API; writes to Hive on success |
| M-015 | Task filter/sort bottom sheet | Chips for active filters; "Clear all" button |
| M-016 | Task detail screen | All fields displayed; attachment count shown (tappable in SPR-003-MB) |
| M-017 | Create/edit task form | All fields: title (required), description, address, priority, type, start_at, end_at |
| M-018 | Drag-to-reorder (ReorderableListView) | Emit PATCH on drag-end; optimistic UI update |
| M-019 | Task completion button | Calls complete endpoint; reads `gamification_delta`; refreshes hero section |
| M-020 | Task cancel action | Swipe-to-dismiss or long-press menu; confirm dialog before PATCH |
| M-021 | Overdue indicator | Red date chip on overdue tasks (`is_overdue: true`) |
| M-022 | Offline read (Hive fallback) | `TaskRepository.getTasks()` falls back to Hive when offline |
| M-023 | Offline write guard | `ConnectivityCubit` checked before any create/edit/complete/cancel |

---

## Technical Notes

### TaskListBloc Event/State Design
```dart
// Events
class LoadTasks extends TaskListEvent {
  final TaskFilter? filter;
}
class ReorderTask extends TaskListEvent {
  final String taskId;
  final int newSortOrder;
}
class CompleteTask extends TaskListEvent { final String taskId; }
class CancelTask extends TaskListEvent { final String taskId; }

// Key state
class TaskListLoaded extends TaskListState {
  final List<Task> tasks;
  final TaskFilter activeFilter;
  final bool isOffline;   // drives UI disable states
}
```

### Overdue Display
```dart
// In task_tile.dart
if (task.isOverdue) {
  return Chip(
    label: Text(formatDate(task.endAt!)),
    backgroundColor: Colors.red.shade100,
    labelStyle: TextStyle(color: Colors.red.shade800),
    avatar: Icon(Icons.warning_amber, size: 16, color: Colors.red),
  );
}
```

### Gamification Hero Refresh After Completion
After `POST /tasks/:id/complete` returns `gamification_delta`, emit a `GamificationUpdated` event to `GamificationCubit` with the delta data. The hero section rebuilds without a separate API call.

```dart
// After successful complete
final delta = response.gamificationDelta;
context.read<GamificationCubit>().applyDelta(delta);
// If badges awarded, show BadgeAwardOverlay (Sprint 4 — stub for now)
```

### Offline Guard
```dart
// TaskListBloc — on any write event
if (state is TaskListLoaded && (state as TaskListLoaded).isOffline) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('You\'re offline. This action is unavailable.')),
  );
  return;
}
```

---

## Testing Requirements

| Test | Type | Required |
|:-----|:-----|:---------|
| `TaskListBloc: loads tasks → Loaded state` | Unit (bloc_test) | ✅ |
| `TaskListBloc: load when offline → Loaded(isOffline: true)` | Unit (bloc_test) | ✅ |
| `TaskListBloc: filter by OVERDUE` | Unit | ✅ |
| `TaskListBloc: complete task → applies delta` | Unit | ✅ |
| `TaskTile widget: overdue chip visible when is_overdue=true` | Widget | ✅ |
| `TaskFormCubit: submit without title → error state` | Unit | ✅ |

---

## Architect Audit Checklist

- [ ] Drag-to-reorder: `PATCH /tasks/:id/sort-order` called (not a full PATCH of all fields)
- [ ] Filter chips reflect active filter state; loading spinner during API call
- [ ] Offline Hive fallback confirmed by disabling network on device
- [ ] `is_overdue: true` tasks display red date chip — not just colour-coded row
- [ ] Hero section visibly updates streak count after task completion (even as placeholder)
