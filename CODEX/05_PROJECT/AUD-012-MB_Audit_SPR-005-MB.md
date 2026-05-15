---
id: AUD-012-MB
title: "Architect Audit — SPR-005-MB Recurring Tasks Mobile"
type: audit
status: APPROVED
sprint: SPR-005-MB
pr_branch: feature/M-036-recurring-tasks
commit: 187f8f1
auditor: architect
created: 2026-05-15
updated: 2026-05-15
---

> **BLUF:** SPR-005-MB **APPROVED**. 13-file sprint delivering the complete recurring task UI: `RecurrenceSchedulePicker` (Daily/Weekdays/Weekly/Custom with day-picker), `RecurringEditScopeDialog` (shown BEFORE form navigation, aborts on dismiss), `TaskFormCubit` scope/rrule integration, `?scope=` query param on PATCH/DELETE, 🔁 chip in task list, and inline `INVALID_RRULE` error routing. Two thoughtful design choices noted: (1) scope dialog correctly skips `isDetached` instances; (2) router updated for backwards compatibility. No findings. **Merge immediately.**

# Architect Audit — SPR-005-MB

---

## Audit Scope

| Item | Value |
|:-----|:------|
| Sprint | SPR-005-MB — Recurring Tasks Mobile |
| PR Branch | `feature/M-036-recurring-tasks` |
| Commit | `187f8f1` |
| Files Changed | 13 |
| Contracts Audited Against | CON-002 §3 (`?scope=` on PATCH/DELETE), PRJ-001 §5.4 |

---

## BCK Tasks Delivered

| MB ID | Task | Status |
|:------|:-----|:-------|
| M-036 | Recurring toggle (segmented TaskType button in task form) | ✅ PASS |
| M-037 | `RecurrenceSchedulePicker` — Daily, Weekdays, Weekly (day picker), Custom RRULE | ✅ PASS |
| M-038 | `RecurringEditScopeDialog` — shown BEFORE form for recurring instances | ✅ PASS |
| M-039 | 🔁 chip in `TaskTile` for recurring instances | ✅ PASS |

---

## RecurrenceSchedulePicker Audit (M-037)

| Check | Result |
|:------|:-------|
| 4 presets: Daily, Weekdays, Weekly, Custom | ✅ |
| `kDailyRRule = 'FREQ=DAILY'` | ✅ |
| Weekdays preset: `'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR'` | ✅ |
| Weekly preset: day-chip multi-selector (Mon–Sun), minimum 1 day guard | ✅ Inline error if `_selectedDays.isEmpty` |
| Custom preset: raw `TextFormField` with `errorText` prop wired to `INVALID_RRULE` | ✅ |
| `errorText` shown for non-custom presets too (API may reject any RRULE) | ✅ |
| `initState()` detects existing RRULE and restores correct preset on edit | ✅ |
| `_customCtrl` disposed in `dispose()` — no memory leak | ✅ |
| `WidgetsBinding.addPostFrameCallback` used to emit initial value post-build | ✅ Avoids setState-in-build error |
| All interactive elements have testable `Key` values | ✅ `rrule_preset_daily`, `rrule_day_MO` etc. |

---

## RecurringEditScopeDialog Audit (M-038)

| Check | Result |
|:------|:-------|
| Shown BEFORE navigating to the edit form — `await` in `task_detail_screen.dart` | ✅ |
| `scope == null` (dismissed) → `return` — form navigation **aborted** | ✅ Critical |
| Shown only for `taskType == TaskType.recurring && !task.isDetached` | ✅ Correct — detached instances are already 🔓 from the series; scope n/a |
| NOT shown for new task creation | ✅ Only wired in the edit code path |
| NOT shown for ONE_TIME tasks | ✅ Guard on `taskType` |
| Returns `RecurringEditScope` via `Navigator.of(context).pop(scope)` | ✅ Type-safe `showModalBottomSheet<RecurringEditScope>` |
| Both options have semantic `Key` values: `scope_this_only`, `scope_this_and_future` | ✅ |

---

## TaskFormCubit Audit

| Check | Result |
|:------|:-------|
| `setScope(RecurringEditScope)` sets `_scope` before `submitEdit`/`deleteTask` | ✅ |
| `submitEdit` passes `scope: _scope` → `taskRepository.updateTask()` | ✅ |
| `deleteTask` passes `scope: _scope` → `taskRepository.deleteTask()` | ✅ |
| `_validateRRule`: RECURRING + empty rrule → `TaskFormError(isRRuleError: true)` | ✅ |
| `_mapRepoError`: `INVALID_RRULE` in exception message → `isRRuleError: true` | ✅ |
| `TaskFormError.isRRuleError` drives inline error on `RecurrenceSchedulePicker` | ✅ |
| Sentinel `_deletedTask` used for `TaskFormSuccess` on delete — avoids nullable | ✅ |

---

## TaskRepository Scope Param Audit

```dart
// updateTask
queryParameters: scope != null ? {'scope': scope.toApiParam()} : null

// deleteTask
queryParameters: scope != null ? {'scope': scope.toApiParam()} : null
```

| Check | Result |
|:------|:-------|
| `?scope=this_only` / `?scope=this_and_future` — matches CON-002 §3 exactly | ✅ |
| `scope == null` → `queryParameters: null` — omits param for ONE_TIME tasks | ✅ |
| Both `updateTask` and `deleteTask` carry scope | ✅ |

---

## TaskTile Recurring Chip Audit (M-039)

```dart
if (task.recurringRuleId != null && !task.isDetached)
  const _RecurringChip()
```

| Check | Result |
|:------|:-------|
| Chip shown when `recurringRuleId != null AND !isDetached` | ✅ Detached = already split, no longer shows as series member |
| Key: `task_tile_recurring_chip` | ✅ |
| Emoji: 🔁 | ✅ |

---

## Router & Out-of-Scope Files Audit

| File | Change | Justified? |
|:-----|:-------|:-----------|
| `app_router.dart` | Task edit route now accepts `Task` OR `TaskEditExtra` extra | ✅ — backwards compatibility for any existing bare-Task push |
| `gamification_cubit_test.dart` | `GamificationStateData` construction updated | ✅ — `Task` model field change required test data update |
| `badge_shelf_widget_test.dart` | Same minor model update | ✅ |

---

## Test Coverage Audit

| Test Group | Scenarios | Pass |
|:-----------|:----------|:-----|
| `TaskFormCubit — submit (create)` | success, empty title error, title too long | ✅ |
| `TaskFormCubit — recurring (create, M-036)` | RECURRING with rrule → success; RECURRING without rrule → `isRRuleError: true` | ✅ |
| `TaskFormCubit — scope (edit, M-038)` | `thisOnly` scope → PATCH with `this_only`; `thisAndFuture` scope → PATCH with `this_and_future` | ✅ |
| `task_tile_recurring_test.dart` | Recurring task → 🔁 chip visible; ONE_TIME task → no chip; detached → no chip | ✅ |

---

## Design Observations (Positive)

1. **`isDetached` guard on scope dialog**: The spec said "shown for ALL RECURRING tasks" but the agent correctly reasoned that `isDetached == true` means the instance was already split from the series (via a prior `this_only` edit), so scope is meaningless — showing the dialog would confuse users. This is the right behaviour and matches PRJ-001 intent.

2. **`TaskEditExtra` backwards compatibility in router**: Rather than breaking the bare–`Task` push route (which other screens might use), the agent added a union-style `if (extra is Task) / else if (extra is TaskEditExtra)` guard. Clean.

---

## Findings

**None.**

---

## Decision

**APPROVED — merge to `develop`.**

With this merge, the mobile app is **MVP-complete** on the feature front.
