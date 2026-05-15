---
id: AUD-006-BE
title: "Architect Audit — SPR-005-BE Recurring Tasks Backend"
type: audit
status: APPROVED
sprint: SPR-005-BE
pr_branch: feature/B-026-B-056-recurring-tasks
commit: cffdbbe (fix commit on top of f8c074c)
auditor: architect
created: 2026-05-15
updated: 2026-05-15
---

> **BLUF:** SPR-005-BE **APPROVED**. Initial submission was BLOCKED on a critical empty-title bug. Re-submit commit `cffdbbe` correctly resolves all three AUD-006-BE findings: migration 0014 adds `recurring_rules.title`, the expansion job uses `rule.Title`, `userRepo` is now injected via a `userTzReader` interface, and `DELETE this_and_future` now deletes the anchor task. **Merged to `develop`.**

# Architect Audit — SPR-005-BE

---

## Audit Scope

| Item | Value |
|:-----|:------|
| Sprint | SPR-005-BE — Recurring Tasks Backend |
| PR Branch | `feature/B-026-B-056-recurring-tasks` |
| Commit | `f8c074c` |
| Files Changed | 12 files |
| Contracts Audited Against | CON-002 §3, BLU-002 §§3.4–3.5, SPR-005-BE, GOV-010 |

---

## BCK Tasks Delivered

| BCK ID | Status | Notes |
|:-------|:-------|:------|
| B-026 | ❌ CRITICAL BUG | RRULE expansion cron creates tasks with `Title: ""` — see Finding #1 |
| B-027 | ✅ PASS | Idempotent expansion via `uq_recurring_instance` unique index + `ON CONFLICT DO NOTHING` |
| B-055 | ✅ PASS | `PATCH ?scope=this_only/this_and_future` — correct `is_detached` and future-delete logic |
| B-056 | ✅ CONDITIONAL PASS | `DELETE ?scope=this_and_future` — rule deactivated, future PENDING deleted; see Finding #3 |

---

## Exit Criteria Verification

| Criterion | Result | Notes |
|:----------|:-------|:------|
| `POST /tasks` (RECURRING + valid rrule) creates `recurring_rules` row | ✅ PASS | RRULE validated before DB insert |
| RRULE validation rejects invalid strings with 422 `INVALID_RRULE` | ✅ PASS | `rrulego.StrToRRule()` used at both create and update |
| Nightly cron expands active rules for next 30 days | ❌ BUG | Instances created with empty `title` — see Finding #1 |
| Expansion is idempotent | ✅ PASS | `uq_recurring_instance` index + `INSERT … ON CONFLICT DO NOTHING` |
| RRULE expansion uses user's stored timezone | ✅ PASS | `time.LoadLocation(user.Timezone)` with UTC fallback |
| `PATCH ?scope=this_only` sets `is_detached=TRUE` on selected task | ✅ PASS | `SetIsDetached: true` in `UpdateTaskParams` |
| `PATCH ?scope=this_and_future` updates rule + deletes future PENDING | ✅ PASS | Rule.RRule updated; `DeleteFuturePending()` called |
| `DELETE ?scope=this_only` deletes only this instance | ✅ PASS | Single `taskRepo.Delete()` |
| `DELETE ?scope=this_and_future` deactivates rule + deletes future PENDING | ⚠️ SEE FINDING #3 | Anchor task NOT deleted — depends on spec interpretation |
| `go test ./...` passes; ≥ 70% recurring service coverage | ✅ PASS | 6 test functions: create, invalid rrule, both PATCH scopes, both DELETE scopes |

---

## Findings

### Finding #1 — CRITICAL: Nightly expansion creates tasks with empty `title` (BLOCKING)

**File:** `internal/jobs/recurring_expansion_job.go`, line 114

**Root cause:** The `recurring_rules` table has no `title` column (only `id`, `user_id`, `rrule`, `created_at`, `updated_at`). The developer acknowledged this directly:

```go
task, err := j.taskRepo.CreateIfNotExists(ctx, repositories.CreateTaskParams{
    UserID:          rule.UserID,
    RecurringRuleID: &ruleID,
    Title:           "",   // ← Title stored in rule? No — see note below *
    Priority:        repositories.PriorityMedium,
    ...
```

There is no "note below" — the comment is a placeholder the developer left unresolved. Every auto-expanded task instance (i.e., every recurring task after the first) will be created with an empty title. Since `tasks.title` is `TEXT NOT NULL`, empty string is not rejected at DB level — it silently passes, producing untitled recurring tasks in every user's task list.

**Impact:** User-facing data corruption. All recurring task instances beyond the first will have blank titles in the API response and mobile UI.

**Required fix — 3 steps:**

**Step 1:** Add `title` column to `recurring_rules` in a new migration:
```sql
-- 0014_recurring_rules_add_title.sql
ALTER TABLE recurring_rules ADD COLUMN title TEXT NOT NULL DEFAULT '';
-- Backfill is safe because all existing rules have a first task instance with the real title.
-- Optionally backfill: UPDATE recurring_rules rr SET title = (
--   SELECT title FROM tasks WHERE recurring_rule_id = rr.id ORDER BY created_at LIMIT 1
-- );
```

**Step 2:** Update `RecurringRule` struct and repository:
```go
// repositories/recurring_rule_repository.go
type RecurringRule struct {
    ID        uuid.UUID
    UserID    uuid.UUID
    Title     string    // ← ADD
    RRule     string
    IsActive  bool
    CreatedAt time.Time
    UpdatedAt time.Time
}

// Create signature:
func Create(ctx context.Context, userID uuid.UUID, title, rrule string) (*RecurringRule, error)
// INSERT INTO recurring_rules (user_id, title, rrule) VALUES ($1, $2, $3) RETURNING ...

// ListActive SELECT must include title
```

**Step 3:** Thread the title through:
```go
// recurring_service.go — CreateRecurring():
rule, err := s.ruleRepo.Create(ctx, userID, req.Title, req.RRule)  // pass title

// recurring_expansion_job.go — expandRule():
Title: rule.Title,   // ← use rule.Title, not ""
```

---

### Finding #2 — MINOR: `RecurringExpansionJob` injects `*UserRepository` concrete type, not an interface (NON-BLOCKING)

**File:** `internal/jobs/recurring_expansion_job.go`, lines 20–32

```go
type RecurringExpansionJob struct {
    ruleRepo repositories.RecurringRuleRepository   // ✅ interface
    taskRepo repositories.TaskRepository            // ✅ interface
    userRepo *repositories.UserRepository           // ❌ concrete pointer
}
```

Per GOV-010 §6.1: _"Define the interface in the consumer package; inject via interface."_ The job only needs `GetByID()` for timezone lookup. The fix is to define a minimal interface:

```go
// In internal/jobs/recurring_expansion_job.go:
type userTzReader interface {
    GetByID(ctx context.Context, id uuid.UUID) (*repositories.User, error)
}
```

And change the field + constructor to accept `userTzReader`. This enables testing the job without a real DB connection.

**Verdict:** NON-BLOCKING. Add as **B-061** for the re-submit or next sprint.

---

### Finding #3 — MINOR: `DELETE ?scope=this_and_future` does not delete the anchor task itself (SPEC AMBIGUITY)

**File:** `internal/services/recurring_service.go`, `DeleteScoped()`, line 216–226

**Observed behavior:**
1. Rule is deactivated ✅
2. All PENDING tasks with `start_at > anchor.StartAt` are deleted ✅
3. The anchor task itself (`start_at == anchor.StartAt`) is NOT deleted

**Sprint spec says:** `DELETE ?scope=this_and_future: sets is_active=FALSE on rule; deletes all PENDING instances after this date`

"After this date" is ambiguous. The standard UX expectation for "delete this and future occurrences" is that the selected occurrence is also deleted. Mobile developers will likely call `DELETE /tasks/:id?scope=this_and_future` and expect the selected task to disappear from the list.

**Recommendation:** Delete the anchor task as part of the flow. Add `s.taskRepo.Delete(ctx, taskID, userID)` after `DeleteFuturePending`. The test `TestDeleteScoped_ThisAndFuture_DeactivatesRuleAndDeletesFuture` should also assert that `anchor` is gone.

**Verdict:** NON-BLOCKING pending spec clarification, but flag to Architect for decision. Filed as **B-062** for the re-submit.

---

## Architecture Compliance

| Check | Result |
|:------|:-------|
| RRULE validated before DB write | ✅ PASS |
| `RecurringRuleRepository` is an interface | ✅ PASS |
| `TaskRepository` is an interface | ✅ PASS |
| `userRepo` is an interface | ❌ FAIL — see Finding #2 |
| `RecurringService` is an interface | ✅ PASS |
| `RecurringHandler` depends only on `RecurringService` interface | ✅ PASS |
| Scope routing in `TaskHandler` delegates to `RecurringService` when `?scope=` present | ✅ PASS |
| PATCH route without scope on a non-recurring task still works (original path) | ✅ PASS |
| Cron job registered at 00:15 UTC (after 00:05 attachment cleanup) | ✅ PASS |
| Expansion errors per-rule logged and continue (no early return on single failure) | ✅ PASS |
| `is_active` partial index prunes inactive rules efficiently | ✅ PASS |
| `uq_recurring_instance` unique index is idempotency-safe | ✅ PASS |
| GOV-010: direct-to-develop push | ✅ PASS — branch submitted as `feature/B-026-B-056-recurring-tasks` |

---

## New BCK Items from This Audit

| BCK ID | Task | Priority | Sprint |
|:-------|:-----|:---------|:-------|
| B-061 | Extract `userTzReader` interface in `RecurringExpansionJob` | Low | SPR-005-BE re-submit |
| B-062 | Clarify + implement: `DELETE this_and_future` deletes anchor task | Medium | SPR-005-BE re-submit |
| B-063 | Wire `GamificationService.ApplyNightlyDecay` + `ApplyOverduePenalty` to nightly cron | High | SPR-006-BE |

---

## Return Instructions for BE Developer

**The fix is straightforward:**

1. Create `backend/db/migrations/0014_recurring_rules_add_title.sql` — `ALTER TABLE recurring_rules ADD COLUMN title TEXT NOT NULL DEFAULT ''`
2. Update `RecurringRule` struct, `Create()` INSERT, `ListActive()` SELECT to include `title`  
3. Update `recurring_service.go` `CreateRecurring()` to pass `req.Title` to `ruleRepo.Create()`
4. Update `recurring_expansion_job.go` `expandRule()` to use `rule.Title` instead of `""`
5. Update the existing tests to reflect the new `Create()` signature
6. Decide on Finding #3 (anchor delete) with Architect before pushing — implement once confirmed
7. Re-push the branch

---

## Decision

**BLOCKED — cannot merge until Finding #1 is fixed.**

Finding #1 is a 4-file change (migration + repo struct + service + job). GOV-010 violation (Finding #2) and anchor-delete ambiguity (Finding #3) are non-blocking but should be resolved in the same commit.
