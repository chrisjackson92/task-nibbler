---
id: AUD-011-BE
title: "Architect Audit — SPR-007-BE Gamification Nightly Cron"
type: audit
status: APPROVED
sprint: SPR-007-BE
pr_branch: feature/B-063-gamification-nightly-cron
commit: 767e34e
auditor: architect
created: 2026-05-15
updated: 2026-05-15
---

> **BLUF:** SPR-007-BE **APPROVED**. 8-file sprint — noticeably tighter implementation than the spec skeleton: agent correctly identified that `ApplyNightlyDecay`/`ApplyOverduePenalty` already take a `userID`, so the job fans out across all users via `ListAllUserIDs` + `CountOverdueForUser` rather than the simpler single-call design in the spec. Interfaces are minimal and consumer-defined. Error handling is per-user (one failure doesn't block others). 5 test scenarios cover all error paths including the no-overdue early-exit. All "out-of-scope" repository changes are required to satisfy the interface contracts. No findings. **Merge immediately.**

# Architect Audit — SPR-007-BE

---

## Audit Scope

| Item | Value |
|:-----|:------|
| Sprint | SPR-007-BE — Gamification Nightly Cron |
| PR Branch | `feature/B-063-gamification-nightly-cron` |
| Commit | `767e34e` |
| Files Changed | 8 |
| BCK Item | B-063 |

---

## Files Audit

| File | Expected | Result |
|:-----|:---------|:-------|
| `internal/jobs/gamification_nightly_job.go` | New — job + 3 interfaces | ✅ IN SCOPE |
| `internal/jobs/gamification_nightly_job_test.go` | New — 5 test scenarios | ✅ IN SCOPE |
| `cmd/api/main.go` | Modified — gocron registration at 00:30 UTC | ✅ IN SCOPE |
| `internal/repositories/auth_repository.go` | Not specified — but adds `ListAllUserIDs` required by `userLister` interface | ✅ JUSTIFIED |
| `internal/repositories/task_repository.go` | Not specified — but adds `CountOverdueForUser` to interface + impl required by `overdueCounter` | ✅ JUSTIFIED |
| `internal/services/recurring_service_test.go` | Not specified — adds `CountOverdueForUser` stub to mock `TaskRepository` | ✅ JUSTIFIED (interface expanded) |
| `internal/services/task_service_test.go` | Not specified — same mock stub | ✅ JUSTIFIED (interface expanded) |
| `CODEX/05_PROJECT/HDO-004-BE_Handoff_SPR-007-BE.md` | Agent handoff | ✅ |

---

## Job Design Audit

> **Note:** The spec skeleton showed a simpler design (`ApplyNightlyDecay(ctx)` without `userID`, single call). The agent correctly identified that the existing service signatures take `(ctx, userID)`, requiring the job to fan-out across users. This is the correct production-ready design.

| Check | Result |
|:------|:-------|
| 3 minimal interfaces: `GamificationServicer`, `userLister`, `overdueCounter` | ✅ Defined in `jobs` package (consumer) — GOV-010 §6.1 compliant |
| Fan-out: `ListAllUserIDs` → iterate → per-user decay + count + penalty | ✅ |
| Decay error: logged at ERROR, increments `decayErr` counter, does NOT return — penalty still runs for that user | ✅ |
| Overdue count = 0: `continue` — penalty call skipped (no unnecessary DB write) | ✅ |
| Overdue count error: logged at ERROR, `continue` — cannot compute penalty without count | ✅ |
| Penalty error: logged at ERROR, increments `penaltyErr` counter, loop continues to next user | ✅ |
| Summary log at job end: `user_count`, `decay_errors`, `penalty_errors` | ✅ GOV-006 structured logging |
| No `os.Exit` or `log.Fatal` inside `Run()` | ✅ |
| `context.Background()` created at `Run()` entry — not stored on struct | ✅ |

---

## Repository Additions Audit

### `UserRepository.ListAllUserIDs`

```sql
SELECT id FROM users ORDER BY id
```

| Check | Result |
|:------|:-------|
| Returns `[]uuid.UUID` — correct type for fan-out | ✅ |
| `rows.Close()` deferred immediately after `Query` | ✅ No connection leak |
| `rows.Err()` checked after iteration | ✅ |
| Scale note in docstring: "add pagination if user count exceeds 10k" | ✅ Honest and appropriate for MVP |

### `TaskRepository.CountOverdueForUser`

```sql
SELECT COUNT(*) FROM tasks
WHERE user_id = $1 AND status = 'PENDING'
  AND end_at IS NOT NULL AND end_at < NOW()
```

| Check | Result |
|:------|:-------|
| `end_at IS NOT NULL` guard prevents NULL comparison returning true | ✅ |
| `status = 'PENDING'` — only unresolved tasks count as overdue | ✅ Correct; CANCELLED/COMPLETED excluded |
| `end_at < NOW()` — consistent with `is_overdue` definition in task service | ✅ |
| Added to `TaskRepository` interface — all mocks updated accordingly | ✅ |

---

## `main.go` Registration Audit

```go
gocron.CronJob("30 0 * * *", false)   // 00:30 UTC
```

| Check | Result |
|:------|:-------|
| Cron expression `30 0 * * *` = 00:30 UTC daily | ✅ |
| Same gocron v2 API pattern as existing `AttachmentCleanupJob` + `RecurringExpansionJob` | ✅ |
| `log.Fatalf` on registration error — acceptable at startup, not inside `Run()` | ✅ |
| `gamNightlyJob.Run()` wrapped in anonymous func with entry log | ✅ |

### Full nightly cron schedule

| Time UTC | Job | Status |
|:---------|:----|:-------|
| 00:05 | `AttachmentCleanupJob` | previously registered |
| 00:15 | `RecurringExpansionJob` | previously registered |
| **00:30** | **`GamificationNightlyJob`** | ✅ registered this sprint |

---

## Test Coverage Audit

| Test | Scenario | Pass |
|:-----|:---------|:-----|
| `Run_Success` | 2 users, 2 overdue each — decay + penalty called for all | ✅ |
| `Run_NoOverdue` | 1 user, 0 overdue — decay called, penalty NOT called | ✅ |
| `Run_DecayError_PenaltyStillRuns` | Decay errors for all users — penalty still attempted for all | ✅ |
| `Run_PenaltyError_DoesNotAbort` | Penalty errors for all users — both users still processed in full | ✅ |
| `Run_UserListError` | `ListAllUserIDs` fails — early return, no decay/penalty calls | ✅ |

All mocks are struct-based (not interface mocking library) — deterministic and dependency-free. ✅

---

## Findings

**None.**

---

## Decision

**APPROVED — merge to `develop`.**

Closes B-063. The backend is now MVP-complete pending SPR-007-BE merge.
