---
id: SPR-002-BE
title: "Sprint 2 — Task CRUD Backend"
type: sprint
status: AUDITED_WITH_NOTES
assignee: coder
agent_boot: AGT-002-BE_Backend_Developer_Agent.md
sprint_number: 2
track: backend
estimated_days: 4
blocked_by: "None"
related: [BLU-002, BLU-003, CON-002, AUD-002-BE]
created: 2026-05-14
updated: 2026-05-15
---

> **BLUF:** Implement full Task CRUD with status model, filter/sort, overdue detection, sort-order management, gamification state initialisation, and the task completion endpoint. By the end, all task endpoints work, gamification state row is created on register, and task completion updates streak + tree health.

# Sprint 2-BE — Task CRUD Backend

---

## Pre-Conditions

- [x] `SPR-001-BE` Architect audit PASSED (AUD-001-BE — APPROVED_WITH_NOTES 2026-05-15)
- [x] Human must merge `feature/B-001-backend-scaffold` → `develop` and fork from `develop`
- [ ] Read `CON-002_API_Contract.md` §3 (Task routes) in full
- [ ] Read `BLU-002_Database_Schema.md` §§3.4–3.5, 3.7 (recurring_rules, tasks, gamification_state)

---

## Exit Criteria

- [ ] `GET /tasks` returns paginated list with all filter/sort params working
- [ ] `POST /tasks` creates task; returns 422 on validation failure
- [ ] `GET /tasks/:id` returns single task with `is_overdue` field
- [ ] `PATCH /tasks/:id` updates fields; `CANCELLED` status sets `cancelled_at`
- [ ] `DELETE /tasks/:id` hard-deletes task row
- [ ] `POST /tasks/:id/complete` sets `completed_at`, increments `streak_count`, applies +5 tree health
- [ ] `PATCH /tasks/:id/sort-order` reorders task
- [ ] `gamification_state` row created automatically when user registers (B-031 requires adding to registration handler)
- [ ] `is_overdue` is computed at read time only — not stored in DB
- [ ] `go test ./...` passes, ≥ 70% coverage on task handlers + services

---

## Task List

| BCK ID | Task | Notes |
|:-------|:-----|:------|
| B-010 | tasks table DB schema + sqlc queries | See BLU-002 §3.5; includes status enum, sort_order, cancelled_at |
| B-011 | Task CRUD (GET, POST, GET/:id, PATCH, DELETE) | CON-002 §3 for exact schemas |
| B-012 | POST /tasks/:id/complete | Returns `gamification_delta` block (see CON-002 §3) |
| B-013 | recurring_rules table schema (basic — expansion in SPR-005-BE) | BLU-002 §3.4 |
| B-014 | go-cron scheduler bootstrap | Register jobs in `main.go`; nightly 00:05 UTC |
| B-038 | Task DB schema additions: status enum, sort_order, cancelled_at, timezone | Confirm task migration includes all fields |
| B-039 | GET /tasks filter params | All query params from CON-002 §3; `overdue` filter is calculated |
| B-040 | OVERDUE calculated field | Computed in repository layer; `is_overdue` never written to DB |
| B-041 | PATCH /tasks/:id/sort-order | Validates `sort_order` is non-negative integer |

---

## Technical Notes

### OVERDUE Implementation
```go
// internal/repositories/task_repository.go
func enrichTask(task *db.Task) *Task {
    t := mapFromDB(task)
    t.IsOverdue = t.Status == TaskStatusPending &&
                 t.EndAt != nil &&
                 t.EndAt.Before(time.Now().UTC())
    return t
}
```

### Task Completion — `gamification_delta` Response
The `POST /tasks/:id/complete` handler must:
1. Mark task as COMPLETED (set `completed_at = now()`)
2. Call `GamificationService.OnTaskCompleted(ctx, userID)` which:
   - Increments `streak_count` if needed (check `last_active_date`)
   - Updates `last_active_date = today`
   - Applies +5 to `tree_health_score` (cap at 100)
   - Sets `has_completed_first_task = true` on first completion
   - Evaluates instant badges: `FIRST_NIBBLE`, `STREAK_*`, `OVERACHIEVER`, `TREE_HEALTHY`, `TREE_THRIVING`
3. Return the CON-002 §3 delta response including any newly awarded badges

### CANCELLED Status
```go
if req.Status == TaskStatusCancelled {
    now := time.Now().UTC()
    params.CancelledAt = &now
}
```
`CANCELLED` tasks have **zero** gamification impact. Do not call `GamificationService`.

### gamification_state Row Creation
Modify the registration handler (service layer) to create a `gamification_state` row in the **same transaction** as the `users` INSERT:
```go
// tx.CreateUser(...)
// tx.CreateGamificationState(ctx, db.CreateGamificationStateParams{UserID: newUser.ID, TreeHealthScore: 50})
```

### Migration to Create This Sprint
```
0005_create_recurring_rules.sql
0006_create_tasks.sql
0007_create_gamification_state.sql  (needed for task completion delta)
```

---

## Testing Requirements

| Test | Type | Required |
|:-----|:-----|:---------|
| `TestListTasks_FilterByStatus` | Integration | ✅ |
| `TestListTasks_FilterByOverdue` | Integration | ✅ |
| `TestListTasks_SortBySortOrder` | Integration | ✅ |
| `TestCreateTask_MissingTitle` | Unit | ✅ |
| `TestCompleteTask_IncrementsStreak` | Integration | ✅ |
| `TestCompleteTask_AwardsFirstNibbleBadge` | Integration | ✅ |
| `TestCancelTask_ZeroGamificationImpact` | Integration | ✅ |
| `TestOverdueTask_IsComputedNotStored` | Unit | ✅ |

---

## Architect Audit Checklist

- [ ] `is_overdue` field absent from `tasks` DB column list (`\d tasks` confirms no such column)
- [ ] `gamification_delta` in complete response matches CON-002 §3 schema exactly
- [ ] `CANCELLED` status does not modify ANY gamification row
- [ ] Filter params validated — invalid `status` value returns `422 VALIDATION_ERROR`
- [ ] `sort_order` default: new task gets `MAX(sort_order) + 1` for the user, not 0
