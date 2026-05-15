---
id: HDO-004-BE
title: "Backend Developer Handoff — SPR-007-BE (Gamification Nightly Cron)"
type: handoff
status: READY
from: coder (Backend Developer Agent)
to: architect
created: 2026-05-15
sprint_completed: SPR-007-BE
branch_submitted: feature/B-063-gamification-nightly-cron
commit: 767e34e
---

> **BLUF:** SPR-007-BE (B-063) is implemented and pushed. The nightly cron now runs `GamificationNightlyJob` at 00:30 UTC. **One important spec-vs-reality divergence** was discovered during implementation and resolved — documented below for the Architect's audit review.

# Handoff — SPR-007-BE

---

## Spec-vs-Reality Divergence

> [!IMPORTANT]
> This section exists specifically to give the Architect full transparency for the audit. The divergence was resolved in a spec-compliant way, but the Architect should confirm the approach.

### SPR-007-BE Spec — `GamificationServicer` interface (parameterless)

The sprint document (lines 72–74) specifies:

```go
type GamificationServicer interface {
    ApplyNightlyDecay(ctx context.Context) error
    ApplyOverduePenalty(ctx context.Context) error
}
```

This implies both methods are **global/fan-out operations** that iterate all users internally.

### Reality — `GamificationService` interface (per-user)

The actual `GamificationService` interface (implemented in SPR-004-BE, unchanged) has:

```go
ApplyNightlyDecay(ctx context.Context, userID uuid.UUID) error
ApplyOverduePenalty(ctx context.Context, userID uuid.UUID, overdueCount int) error
```

These are **per-user operations** — they take a `userID` and (for penalty) an `overdueCount`. The service has no knowledge of all users or their overdue task counts; that is a cross-cutting concern.

### Resolution

Rather than modify `GamificationService` (which would require changing its interface, constructor, and all existing tests), the fan-out responsibility was placed in the **job itself**. This is architecturally correct — the job is the orchestrator, not the service.

The job-level `GamificationServicer` interface was updated to **match the real service signatures**:

```go
// In internal/jobs/gamification_nightly_job.go
type GamificationServicer interface {
    ApplyNightlyDecay(ctx context.Context, userID uuid.UUID) error
    ApplyOverduePenalty(ctx context.Context, userID uuid.UUID, overdueCount int) error
}
```

Two additional consumer-package interfaces were defined (per GOV-010 §6.1):

```go
type userLister interface {
    ListAllUserIDs(ctx context.Context) ([]uuid.UUID, error)
}

type overdueCounter interface {
    CountOverdueForUser(ctx context.Context, userID uuid.UUID) (int, error)
}
```

`GamificationNightlyJob.Run()` performs the fan-out loop, calling the service's per-user methods for each user returned by `userLister`.

### Supporting Additions (not in sprint spec, required by resolution)

| Addition | File | Rationale |
|:---------|:-----|:----------|
| `UserRepository.ListAllUserIDs(ctx)` | `auth_repository.go` | Needed to enumerate all users for fan-out |
| `TaskRepository.CountOverdueForUser(ctx, userID)` | `task_repository.go` | Needed to count overdue tasks per user before calling penalty |

These are pure data-access additions with no schema changes. No migrations required.

### Architect Decision Required

> [!NOTE]
> The Architect should confirm whether the parameterless `GamificationServicer` in the sprint spec was intentional (implying a future refactor of `GamificationService` to be fan-out aware) or whether the per-user approach adopted here is the intended final design. Either interpretation is consistent with GOV-010; the current implementation works correctly either way.

---

## Exit Criteria Verification

| Criterion | Status |
|:----------|:-------|
| `gamification_nightly_job.go` created | ✅ |
| Job registered at 00:30 UTC | ✅ |
| `GamificationServicer` interface in jobs package (not imported from services) | ✅ |
| Decay error does NOT prevent penalty from running | ✅ |
| Unit tests: success + decay error + penalty error paths | ✅ (5 tests) |
| `go build ./...` succeeds | ✅ |
| `go test ./...` passes | ✅ |
| No `os.Exit` or `log.Fatal` in `Run()` | ✅ |

---

## Full Cron Schedule (post SPR-007-BE)

| UTC | Job | File |
|:----|:----|:-----|
| 00:05 | `AttachmentCleanupJob` | `attachment_cleanup_job.go` |
| 00:15 | `RecurringExpansionJob` | `recurring_expansion_job.go` |
| **00:30** | **`GamificationNightlyJob`** | **`gamification_nightly_job.go`** |
