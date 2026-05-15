---
id: SPR-007-BE
title: "Sprint 7 — Gamification Nightly Cron"
type: sprint
status: READY
assignee: coder
agent_boot: AGT-002-BE_Backend_Developer_Agent.md
sprint_number: 7
track: backend
estimated_days: 1
blocked_by: none — all dependencies shipped in SPR-004-BE and SPR-005-BE
related: [BLU-002, CON-002, BCK-001 B-063]
created: 2026-05-15
updated: 2026-05-15
---

> **BLUF:** Small sprint — ~1 day. Wire `GamificationService.ApplyNightlyDecay()` and `ApplyOverduePenalty()` to the existing gocron scheduler in `main.go`. The services and all supporting DB queries already exist (SPR-004-BE). This sprint is purely integration: new job file + scheduler registration + unit test. No schema migrations required.

> [!IMPORTANT]
> **Scope is intentionally tiny.** Do NOT refactor gocron setup, add features, or modify any other job. This sprint exists solely to close B-063, which was explicitly deferred from SPR-004-BE audit (AUD-006-BE) and SPR-006-OPS audit (AUD-008-OPS).

# Sprint 7-BE — Gamification Nightly Cron

---

## Pre-Conditions

- [x] `SPR-004-BE` merged to `develop` — `GamificationService.ApplyNightlyDecay` and `ApplyOverduePenalty` fully implemented and tested
- [x] `SPR-005-BE` merged to `develop` — gocron scheduler in `main.go` registering `AttachmentCleanupJob` + `RecurringExpansionJob`
- [ ] Read `backend/internal/jobs/` — understand existing job pattern before writing a new one
- [ ] Read `backend/internal/services/gamification_service.go` — confirm method signatures

---

## Exit Criteria

- [ ] `internal/jobs/gamification_nightly_job.go` created — wraps both `ApplyNightlyDecay` and `ApplyOverduePenalty` in a single nightly job
- [ ] Job registered in `main.go` at **00:30 UTC** (after recurring expansion at 00:15)
- [ ] Job uses the `GamificationServicer` interface (not the concrete type) — enables mocking in tests
- [ ] Unit test: `TestGamificationNightlyJob_Run` covers success path, decay error, penalty error
- [ ] `go build ./...` succeeds — no import cycles
- [ ] `go test ./...` passes, ≥ 80% coverage on new job file

---

## Task List

| BCK ID | Task | File | Notes |
|:-------|:-----|:-----|:------|
| B-063 | Define `GamificationServicer` interface | `internal/jobs/gamification_nightly_job.go` | Subset: `ApplyNightlyDecay(ctx) error` + `ApplyOverduePenalty(ctx) error` |
| B-063 | Implement `GamificationNightlyJob.Run()` | `internal/jobs/gamification_nightly_job.go` | Call decay first, then penalty; log each outcome |
| B-063 | Register job in gocron scheduler | `cmd/api/main.go` | `s.Every(1).Day().At("00:30").Do(gamNightlyJob.Run)` |
| B-063 | Unit test job file | `internal/jobs/gamification_nightly_job_test.go` | Mock `GamificationServicer`; test success + each error path |

---

## Technical Notes

### New File — `internal/jobs/gamification_nightly_job.go`

```go
package jobs

import (
	"context"
	"log/slog"
)

// GamificationServicer is the interface this job depends on.
// Allows the concrete *GamificationService to be swapped for a mock in tests.
type GamificationServicer interface {
	ApplyNightlyDecay(ctx context.Context) error
	ApplyOverduePenalty(ctx context.Context) error
}

// GamificationNightlyJob runs at 00:30 UTC every day.
// It applies tree-health decay and overdue-task penalties to all active users.
type GamificationNightlyJob struct {
	svc GamificationServicer
	log *slog.Logger
}

func NewGamificationNightlyJob(svc GamificationServicer, log *slog.Logger) *GamificationNightlyJob {
	return &GamificationNightlyJob{svc: svc, log: log}
}

func (j *GamificationNightlyJob) Run() {
	ctx := context.Background()

	if err := j.svc.ApplyNightlyDecay(ctx); err != nil {
		j.log.Error("gamification nightly decay failed", "error", err)
		// Do NOT return — continue to penalty even if decay errors.
	} else {
		j.log.Info("gamification nightly decay applied")
	}

	if err := j.svc.ApplyOverduePenalty(ctx); err != nil {
		j.log.Error("gamification overdue penalty failed", "error", err)
	} else {
		j.log.Info("gamification overdue penalty applied")
	}
}
```

### Registration in `main.go`

Add after the existing `RecurringExpansionJob` registration:

```go
// 00:30 UTC — Gamification nightly decay + overdue penalties (B-063)
gamNightlyJob := jobs.NewGamificationNightlyJob(gamificationService, logger)
if _, err := s.NewJob(
    gocron.DailyJob(1, gocron.NewAtTimes(gocron.NewAtTime(0, 30, 0))),
    gocron.NewTask(gamNightlyJob.Run),
); err != nil {
    log.Fatalf("failed to register GamificationNightlyJob: %v", err)
}
```

> **Note on gocron version:** Check existing job registrations in `main.go` and use the same API version. Do NOT mix v1 and v2 call styles.

### Job Execution Order (full cron schedule after this sprint)

| Time (UTC) | Job | File |
|:-----------|:----|:-----|
| 00:05 | `AttachmentCleanupJob` — delete PENDING attachments + S3 objects | `attachment_cleanup_job.go` |
| 00:15 | `RecurringExpansionJob` — expand rules for next 30 days | `recurring_expansion_job.go` |
| **00:30** | **`GamificationNightlyJob`** — decay + overdue penalty | **`gamification_nightly_job.go`** ← NEW |

---

## Testing Requirements

| Test | Coverage Required |
|:-----|:-----------------|
| `Run()` — both decay and penalty succeed | ✅ |
| `Run()` — decay errors, penalty still runs (no early return) | ✅ |
| `Run()` — penalty errors; decay already ran | ✅ |

```go
// Example test skeleton
func TestGamificationNightlyJob_Run_Success(t *testing.T) {
    mockSvc := &mockGamSvc{} // implements GamificationServicer
    when(mockSvc.ApplyNightlyDecay).thenReturn(nil)
    when(mockSvc.ApplyOverduePenalty).thenReturn(nil)
    job := NewGamificationNightlyJob(mockSvc, slog.Default())
    job.Run() // should not panic; both methods called once
    // assert both called
}

func TestGamificationNightlyJob_Run_DecayError_PenaltyStillRuns(t *testing.T) {
    // decay returns error → penalty must still be called
}
```

---

## Commit Convention

```
feat(gamification): nightly decay + overdue penalty cron job [B-063]
```

Branch: `feature/B-063-gamification-nightly-cron` (fork from `develop`)

---

## Architect Audit Checklist

- [ ] `GamificationServicer` interface defined in the jobs package (not imported from services)
- [ ] Decay error does NOT prevent penalty from running (two separate `if err` blocks, no early return)
- [ ] Job registered at 00:30 UTC — not 00:05 or 00:15 (would conflict with other jobs)
- [ ] Test: mock `GamificationServicer`; does NOT call through to `GamificationService`
- [ ] No `os.Exit` or `log.Fatal` inside `Run()` — log and continue on error
