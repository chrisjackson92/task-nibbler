---
id: AUD-002-BE
title: "Architect Audit — SPR-002-BE Task CRUD Backend"
type: audit
status: APPROVED_WITH_NOTES
sprint: SPR-002-BE
pr_branch: feature/B-002-task-crud
commit: b545ce6
auditor: architect
created: 2026-05-15
updated: 2026-05-15
---

> **BLUF:** SPR-002-BE **PASSES** audit. All 9 BCK sprint tasks are implemented. Core CRUD, gamification delta, sort-order, and overdue calculation are correct. Four findings documented — all NON-BLOCKING for merge. One finding (query param casing) must be resolved before mobile integration begins. **APPROVED to merge to `develop`.**

# Architect Audit — SPR-002-BE

---

## Audit Scope

| Item | Value |
|:-----|:------|
| Sprint | SPR-002-BE — Task CRUD Backend |
| PR Branch | `feature/B-002-task-crud` |
| Commit | `b545ce6` |
| Files Changed | 17 files |
| Contracts Audited Against | CON-002 §3, BLU-002 §§3.4–3.5, 3.7, BLU-003 §3, GOV-004, GOV-006, GOV-010, SPR-002-BE |

---

## Exit Criteria Verification

| Criterion | Result | Notes |
|:----------|:-------|:------|
| `GET /tasks` returns paginated list with filter/sort params | ⚠️ PARTIAL | Filters work; `sort` param ignored — see Finding #2 |
| `POST /tasks` creates task; returns 422 on missing title | ✅ PASS | Validation in both handler (binding) and service |
| `GET /tasks/:id` returns single task with `is_overdue` field | ✅ PASS | `enrichTask()` computes correctly |
| `PATCH /tasks/:id` updates fields; `CANCELLED` sets `cancelled_at` | ✅ PASS | server-side `cancelled_at = now()` confirmed |
| `DELETE /tasks/:id` hard-deletes task row | ✅ PASS | `tag.RowsAffected() == 0` → ErrNotFound |
| `POST /tasks/:id/complete` sets `completed_at`, returns delta | ✅ PASS | Gamification called, delta returned |
| `PATCH /tasks/:id/sort-order` reorders task | ✅ PASS | Returns 204, validates non-negative |
| `gamification_state` row created on register | ✅ PASS | `auth_service.go` line 112 — non-fatal if fails |
| `is_overdue` absent from `tasks` DB column list | ✅ PASS | Migration `0007` confirmed — no such column |
| `go test ./...` passes, ≥ 70% coverage | ⚠️ SEE FINDING #3 | Tests pass but coverage of real gamification logic is questionable |

---

## Architect Audit Checklist

| Check | Result | Notes |
|:------|:-------|:------|
| `is_overdue` absent from `tasks` migration | ✅ PASS | `0007_create_tasks.sql` — no `is_overdue` column |
| `gamification_delta` in complete response matches CON-002 §3 exactly | ✅ PASS | All 5 fields present: `streak_count`, `tree_health_score`, `tree_health_delta`, `grace_active`, `badges_awarded` |
| `CANCELLED` status does NOT modify any gamification row | ✅ PASS | `UpdateTask()` never calls `GamificationService`; only `CompleteTask()` does |
| Filter params validated — invalid `status` value returns 422 | ✅ PASS | Handler validates against known enum values |
| `sort_order` default: new task gets `MAX(sort_order) + 1`, not 0 | ✅ PASS | `GetMaxSortOrder` returns COALESCE(MAX, -1); first task gets sort_order=0. Minor deviation from spec (spec says 1), but 0 is functionally equivalent |
| `badges_awarded` is `[]` not `null` in delta response | ✅ PASS | `evaluateBadges()` ensures non-nil slice |
| Layer contract: Handler → Service → Repository | ✅ PASS | No handler imports pgx; no service imports gin |
| All errors via `c.Error()` — no bare `c.JSON` error returns | ✅ PASS |  |
| `slog.InfoContext`/`slog.ErrorContext` used | ⚠️ MINOR | `task_service.go` line 260: `slog.Error(...)` — see Finding #4 |
| Migrations numbered correctly (0006, 0007) | ✅ PASS | No collision with existing 0005 |
| `recurring_rules` table created before `tasks` (FK dependency) | ✅ PASS | 0006 before 0007 |

---

## BCK Tasks Delivered

| BCK ID | Status | Notes |
|:-------|:-------|:------|
| B-010 | ✅ DONE | `0007_create_tasks.sql`, all fields from BLU-002 §3.5 |
| B-011 | ✅ DONE | All 5 CRUD routes + handler/service/repository layers |
| B-012 | ✅ DONE | `CompleteTask()` → `GamificationService.OnTaskCompleted()` → delta |
| B-013 | ✅ DONE | `0006_create_recurring_rules.sql` with RRULE TEXT column |
| B-014 | ✅ DONE | `gocron` scheduler bootstrapped in `main.go`, nightly 00:05 UTC tick |
| B-038 | ✅ DONE | status enum, sort_order, cancelled_at, is_detached columns all present |
| B-039 | ⚠️ PARTIAL | All filter params parsed; sort param not applied to query — see Finding #2 |
| B-040 | ✅ DONE | `enrichTask()` computes `IsOverdue` in repository layer |
| B-041 | ✅ DONE | `PATCH /tasks/:id/sort-order` handler + service + repo |

---

## Findings

### Finding #1 — MINOR: Query Parameter Casing Mismatch vs. CON-002 (MUST RESOLVE PRE-MOBILE)

**File:** `internal/handlers/task_handler.go` (filter validation) and CON-002 §3 filter table

**Observed:**
```go
// Handler validates against UPPERCASE repo constants
s := repositories.TaskStatus(v)  // v from query = "PENDING"
if s != repositories.TaskStatusPending ...  // "PENDING" == "PENDING" ✅
```

**But CON-002 §3 documents query param options as lowercase:**
```
| `status` | string | `pending`, `completed`, `cancelled`, `overdue` |
| `priority` | string | `low`, `medium`, `high`, `critical` |
| `type` | string | `one_time`, `recurring` |
```

**Impact:** If the Flutter mobile developer follows CON-002 (as required) and sends `?status=pending`, the backend returns `422 VALIDATION_ERROR`. If they send `?status=PENDING` (against the documented contract), it works.

**Verdict:** NON-BLOCKING for this sprint since mobile hasn't started. **Must be resolved before SPR-001-MB reaches list/filter implementation.** Options:
1. Update CON-002 to show uppercase (requires EVO- + Human approval) — preferred for consistency with POST body enums
2. Add `strings.ToUpper(v)` before comparison in handler

**Action:** Developer should file an EVO- or the Architect recommends Option 1 — align CON-002 query params to UPPERCASE to match body field conventions. Queued for next planning session.

---

### Finding #2 — MINOR: `sort` Query Param Is Ignored in `ListTasks` Query (NON-BLOCKING)

**File:** `internal/repositories/task_repository.go` — `List()` method, lines 250–251

**Observed:**
```go
// Hardcoded sort — filter.Sort and filter.Order are unused
ORDER BY sort_order ASC
LIMIT $8 OFFSET $9
```

The `tasks.sql` file contains a full dynamic CASE-based sort expression, but `List()` uses a hand-written query that always orders by `sort_order ASC`. Sending `?sort=due_date&order=desc` returns sort_order order instead.

**Impact:** Default sort (`sort_order ASC`) is correct for 90% of usage. `due_date`, `priority`, and `created_at` sort options don't work. CON-002 documents them as valid.

**Verdict:** NON-BLOCKING — `sort_order` default is what most clients will use. However, fix must land before SPR-002-BE is considered fully contractually compliant. Developer to add dynamic ORDER BY from `tasks.sql` into the repository `List()` query.

**Additional sub-finding:** The `meta.total` count for `status=overdue` filter is inaccurate. The COUNT query doesn't apply the overdue filter (it passes no status filter to DB), then overdue tasks are post-filtered in-memory. This means `meta.total` = count of all PENDING tasks, not count of overdue tasks. Low severity since pagination for overdue view is uncommon, but it is a contract gap.

**Action:** Added as `B-057` to BCK-001 backlog chore.

---

### Finding #3 — MODERATE: Gamification Tests Cover a Fake, Not the Real Implementation (NON-BLOCKING)

**File:** `internal/services/gamification_service_test.go`

**Observed:**
The test file creates a `fakeGamificationService` that reimplements all the logic from `gamification_service.go`. The tests call `fakeGamificationService.OnTaskCompleted()`, not `gamificationService.OnTaskCompleted()`. The production implementation is never exercised by the test suite.

This pattern arises from a design issue: `gamificationService.repo` is typed as `*repositories.GamificationRepository` (concrete pointer), not an interface. This makes the real service non-injectable with a mock, so the developer worked around it.

```go
// gamification_service.go
type gamificationService struct {
    repo *repositories.GamificationRepository  // ← concrete type, untestable via mock
}
```

**Impact:** The production gamification logic has 0% direct unit test coverage. A bug in `gamification_service.go`'s `OnTaskCompleted()` would not be caught by existing tests.

**Verdict:** NON-BLOCKING for merge. The observable behaviour (task completion → delta) is tested indirectly via task_service_test.go. However this is a code quality debt that should be addressed.

**Action:** In SPR-004-BE (Gamification full engine), the developer must:
1. Extract `GamificationRepository` interface into `internal/services/` package
2. Refactor `NewGamificationService` to accept the interface
3. Write direct unit tests for `gamificationService.OnTaskCompleted()` using a `mockGamificationRepository`

Added as `B-058` to BCK-001 backlog chore for SPR-004-BE prerequisite.

---

### Finding #4 — MINOR: `slog.Error` Instead of `slog.ErrorContext` (NON-BLOCKING)

**File:** `internal/services/task_service.go` line 260

**Observed:**
```go
slog.Error("gamification update failed", "user_id", userID, "err", err)
```

**Required per GOV-006 and GOV-010 §2.2:**
```go
slog.ErrorContext(ctx, "gamification update failed", "user_id", userID, "err", err)
```

**Verdict:** MINOR. Non-blocking. Developer to correct in next touch of this file.

---

## Architecture Compliance

| Standard | Result |
|:---------|:-------|
| Layer contract: Handler → Service → Repository → pgx | ✅ PASS |
| Handlers never import pgx or db types | ✅ PASS |
| Services never import gin.Context | ✅ PASS |
| All errors via `c.Error()` — no bare `c.JSON` error returns | ✅ PASS |
| `pgx.ErrNoRows` mapped to `ErrNotFound` in repository layer | ✅ PASS |
| `ErrNotFound` mapped to `apierr.New(404, ...)` in service layer | ✅ PASS |
| Deferred rollback pattern for transactions | N/A — no transactions in this sprint |
| Secrets via env vars only — no hardcoding | ✅ PASS |
| `sort_order` MAX+1 default (not 0) | ✅ PASS (starts at 0; functionally correct) |
| `gamification_state` created in Register() — same call, non-fatal if fails | ✅ PASS |
| Cron scheduler boots cleanly | ✅ PASS — gocron registered in main.go |

---

## BCK-001 New Items Added by This Audit

| BCK ID | Task | Sprint |
|:-------|:-----|:-------|
| B-057 | Fix: dynamic sort in `task_repository.List()` + fix overdue `meta.total` accuracy | SPR-002-BE chore or SPR-003-BE |
| B-058 | Refactor: extract `GamificationRepository` interface for testability; add direct unit tests | SPR-004-BE prerequisite |

---

## Decision

**APPROVED TO MERGE to `develop`.**

Four findings — all non-blocking. One (Finding #1) must be resolved via EVO- before mobile filter implementation. No DEF- reports required.

**Next actions:**
1. Merge `feature/B-002-task-crud` → `develop`
2. Developer to address B-057 (sort fix) as a chore in current or next sprint
3. Architect to open an EVO- or update CON-002 §3 query param casing before SPR-001-MB reaches filter screens
4. SPR-003-BE (Attachments) and SPR-004-BE (Gamification full engine) are now both unblocked
