---
id: SPR-005-MB
title: "Sprint 5 — Recurring Tasks Mobile"
type: sprint
status: READY
assignee: coder
agent_boot: AGT-002-MB_Mobile_Developer_Agent.md
sprint_number: 5
track: mobile
estimated_days: 3
blocked_by: SPR-005-BE + SPR-004-MB (must pass audit)
related: [BLU-004, CON-002, PRJ-001]
created: 2026-05-14
updated: 2026-05-14
---

> **BLUF:** Add recurring task UI to the task create/edit form — RRULE schedule picker, recurring toggle, the edit-scope dialog ("This instance" vs "This and all future"), and visual indicators for recurring task instances in the task list.

# Sprint 5-MB — Recurring Tasks Mobile

---

## Pre-Conditions

- [ ] `SPR-004-MB` Architect audit PASSED
- [ ] `SPR-005-BE` complete — recurring task endpoints live on staging
- [ ] Read `PRJ-001` §5.4 (Recurring Tasks spec — edit scope dialog) in full
- [ ] Read `CON-002_API_Contract.md` §3 (`?scope=` query params on PATCH/DELETE) in full

---

## Exit Criteria

- [ ] Task create/edit form has a "Recurring" toggle switch
- [ ] When toggled ON: frequency picker appears (Daily, Weekly, Custom)
- [ ] Daily/Weekly create standard RRULEs; Custom shows advanced RRULE builder
- [ ] Editing a RECURRING task: edit-scope dialog appears BEFORE the form opens
- [ ] "This instance" → sets `?scope=this_only` on PATCH/DELETE
- [ ] "This and all future" → sets `?scope=this_and_future` on PATCH/DELETE
- [ ] Recurring task instances show a 🔁 chip in the task list
- [ ] `fvm flutter test` passes, ≥ 70% coverage on task form cubit recurring logic

---

## Task List

| BCK ID | Task | Notes |
|:-------|:-----|:------|
| M-036 | Recurring toggle in task form | Toggle switch; when ON shows frequency picker |
| M-037 | Recurrence schedule picker | Preset (Daily/Weekly) + Custom RRULE input |
| M-038 | Edit scope dialog | Bottom sheet: "This instance" / "This and all future" |
| M-039 | Recurring task chip in list | Small 🔁 icon or chip on tasks with `recurring_rule_id != null` |

---

## Technical Notes

### RRULE Builder (Simple Presets)
```dart
// Preset daily
const dailyRRule = 'FREQ=DAILY';
// Preset weekly on selected days
String weeklyRRule(List<String> days) =>
    'FREQ=WEEKLY;BYDAY=${days.join(",")}';  // e.g. 'FREQ=WEEKLY;BYDAY=MO,WE,FR'
```
Custom mode: expose a text field where the user can type a raw RRULE string. The API validates it; if `422 INVALID_RRULE` is returned, show an inline error.

### Edit Scope Dialog Pattern
```dart
// Called BEFORE navigating to edit form — only for RECURRING tasks
Future<RecurringEditScope?> showEditScopeDialog(BuildContext context) {
  return showModalBottomSheet<RecurringEditScope>(
    context: context,
    builder: (_) => Column(children: [
      ListTile(
        title: Text('This task only'),
        subtitle: Text('Edit just this occurrence'),
        onTap: () => Navigator.pop(context, RecurringEditScope.thisOnly),
      ),
      ListTile(
        title: Text('This and all future tasks'),
        subtitle: Text('Edit this occurrence and all that follow'),
        onTap: () => Navigator.pop(context, RecurringEditScope.thisAndFuture),
      ),
    ]),
  );
}
```

### Scope in Form Submission
```dart
// TaskFormCubit — stores chosen scope
enum RecurringEditScope { thisOnly, thisAndFuture }

class TaskFormCubit extends Cubit<TaskFormState> {
  RecurringEditScope? _scope;

  Future<void> submit() async {
    final scopeParam = task.isRecurring ? _scope?.toApiParam() : null;
    await _taskRepo.updateTask(task.id, req, scope: scopeParam);
  }
}
```

---

## Testing Requirements

| Test | Type | Required |
|:-----|:-----|:---------|
| `TaskFormCubit: recurring toggle ON → rrule field required` | Unit | ✅ |
| `TaskFormCubit: scope=thisOnly → PATCH with this_only param` | Unit | ✅ |
| `TaskFormCubit: scope=thisAndFuture → PATCH with this_and_future param` | Unit | ✅ |
| `Task list: recurring task shows 🔁 chip` | Widget | ✅ |

---

## Architect Audit Checklist

- [ ] Edit scope dialog shown for ALL RECURRING tasks before navigating to form — not only "if rrule is set"
- [ ] `?scope=` query param included on every PATCH/DELETE of a recurring task instance
- [ ] Custom RRULE field shows inline error from API `422 INVALID_RRULE` (not a generic error)
- [ ] NEW recurring tasks (creating, not editing) do NOT show scope dialog
