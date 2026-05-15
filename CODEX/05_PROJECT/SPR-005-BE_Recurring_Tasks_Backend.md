---
id: SPR-005-BE
title: "Sprint 5 — Recurring Tasks Backend"
type: sprint
status: MERGED
assignee: coder
agent_boot: AGT-002-BE_Backend_Developer_Agent.md
sprint_number: 5
track: backend
estimated_days: 3
blocked_by: SPR-002-BE (recurring_rules table must exist)
related: [BLU-002, BLU-003, CON-002, PRJ-001]
created: 2026-05-14
updated: 2026-05-14
---

> **BLUF:** Implement the server-side recurring task system: RRULE storage, nightly expansion cron, idempotent instance creation, timezone-aware expansion, and edit/delete scope (this instance only vs. this and all future).

# Sprint 5-BE — Recurring Tasks Backend

---

## Pre-Conditions

- [ ] `SPR-002-BE` Architect audit PASSED (recurring_rules table created)
- [ ] Read `PRJ-001` §5.4 (Recurring Tasks spec — edit scope, RRULE, timezone) in full
- [ ] Read `CON-002_API_Contract.md` §3 PATCH and DELETE routes (`?scope=` param) in full
- [ ] Read `BLU-002_Database_Schema.md` §§3.4–3.5 (recurring_rules + tasks `recurring_rule_id`, `is_detached`) in full
- [ ] `teambition/rrule-go` package added to `go.mod`

---

## Exit Criteria

- [ ] `POST /tasks` with `task_type=RECURRING` and valid `rrule` creates a `recurring_rules` row
- [ ] Nightly cron expands all active rules: concrete tasks created for next 30 days
- [ ] Expansion is idempotent: re-running cron same night creates no duplicates
- [ ] RRULE expansion uses user's stored timezone (not UTC) for "9am daily" rules
- [ ] `PATCH /tasks/:id?scope=this_only`: sets `is_detached=TRUE` on selected task; rule unchanged
- [ ] `PATCH /tasks/:id?scope=this_and_future`: updates rule; deletes all PENDING instances after this task's date; cron regenerates them
- [ ] `DELETE /tasks/:id?scope=this_only`: deletes only this concrete instance
- [ ] `DELETE /tasks/:id?scope=this_and_future`: sets `is_active=FALSE` on rule; deletes all PENDING instances after this date
- [ ] `go test ./...` passes, ≥ 70% recurring service coverage

---

## Task List

| BCK ID | Task | Notes |
|:-------|:-----|:------|
| B-026 | RRULE expansion cron: expand active rules for next 30 days | Timezone-aware; idempotent |
| B-027 | Idempotent expansion: skip existing instances | Check `recurring_rule_id + expected_date` uniqueness |
| B-055 | PATCH /tasks/:id?scope=this_only or this_and_future | Update recurring rule + delete/regen future instances |
| B-056 | DELETE /tasks/:id?scope=this_only or this_and_future | Deactivate rule + delete future PENDING instances |

---

## Technical Notes

### RRULE Expansion Logic (Timezone-Aware)
```go
// internal/jobs/nightly_cron.go — RecurringJob.ExpandRules
func (j *RecurringJob) ExpandRules(ctx context.Context) error {
    rules, _ := j.ruleRepo.ListActive(ctx)
    for _, rule := range rules {
        user, _ := j.userRepo.Get(ctx, rule.UserID)
        loc, _ := time.LoadLocation(user.Timezone) // e.g. "America/New_York"

        rRule, _ := rrule.StrToRRule(rule.RRULE)
        rRule.DTStart = time.Now().In(loc)

        occurrences := rRule.Between(
            time.Now(),
            time.Now().AddDate(0, 0, 30),
            true,
        )
        for _, occ := range occurrences {
            j.taskRepo.CreateIfNotExists(ctx, rule, occ.UTC()) // idempotent
        }
    }
}
```

### Idempotent Task Instance Check
Add a **unique constraint** in the tasks migration:
```sql
-- Unique: one concrete task instance per rule per calendar day
CREATE UNIQUE INDEX uq_recurring_instance
  ON tasks (recurring_rule_id, DATE(COALESCE(start_at, created_at)))
  WHERE recurring_rule_id IS NOT NULL AND is_detached = FALSE;
```
The `CreateIfNotExists` repository method uses `INSERT ... ON CONFLICT DO NOTHING`.

### `this_and_future` Edit Flow
```go
// PATCH ?scope=this_and_future
func (s *RecurringService) UpdateFromThisInstance(ctx context.Context, taskID uuid.UUID, req UpdateTaskReq) error {
    task, _ := s.taskRepo.Get(ctx, taskID)
    // 1. Update the recurring_rule
    s.ruleRepo.Update(ctx, task.RecurringRuleID, req.RRULE)
    // 2. Delete all PENDING instances after this task's start_at
    s.taskRepo.DeleteFuturePending(ctx, task.RecurringRuleID, task.StartAt)
    // 3. Cron will regenerate them on next run (or trigger expansion now)
    return nil
}
```

### `scope` Parameter Default
- `ONE_TIME` tasks: `scope` parameter is ignored
- `RECURRING` tasks where `scope` is absent: return `422 VALIDATION_ERROR` with message "scope parameter required for recurring tasks"

### No API Endpoint for Recurring Rules
There is no `GET /recurring-rules` or `POST /recurring-rules` endpoint. Rules are created implicitly when a `RECURRING` task is created. They are never exposed directly in the API.

---

## Testing Requirements

| Test | Type | Required |
|:-----|:-----|:---------|
| `RecurringJob: expands rule → correct instances in DB` | Unit | ✅ |
| `RecurringJob: run twice → no duplicate instances` | Unit (idempotent check) | ✅ |
| `RecurringJob: timezone-aware → 9am Eastern = 14:00 UTC in DB` | Unit | ✅ |
| `PATCH scope=this_only → is_detached=TRUE, rule unchanged` | Integration | ✅ |
| `PATCH scope=this_and_future → future PENDING instances deleted` | Integration | ✅ |
| `DELETE scope=this_only → only one row deleted` | Integration | ✅ |
| `DELETE scope=this_and_future → rule is_active=FALSE + future rows gone` | Integration | ✅ |

---

## Architect Audit Checklist

- [ ] `uq_recurring_instance` unique index exists (`\d tasks` confirms)
- [ ] Timezone confirmed: user with timezone `America/New_York` gets expansion in Eastern time (not UTC)
- [ ] `scope` absent on RECURRING task returns 422 (not silently applying a default)
- [ ] `recurring_rules.is_active = FALSE` for deactivated rules (not hard-deleted)
- [ ] Nightly cron logs each rule expansion with structured context (`rule_id`, `user_id`, `instances_created`)
