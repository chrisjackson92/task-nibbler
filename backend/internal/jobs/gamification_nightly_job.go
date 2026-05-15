package jobs

import (
	"context"
	"log/slog"

	"github.com/google/uuid"
)

// GamificationServicer is the minimal interface this job depends on.
// It is defined here (consumer package) per GOV-010 §6.1 — not imported from services.
// The concrete *gamificationService satisfies this interface implicitly.
//
// The job performs the fan-out over all users; each call is per-user.
type GamificationServicer interface {
	// ApplyNightlyDecay applies streak reset + tree-health decay for a single user.
	// Returns nil if the user is still in WELCOME state (no-op protected by service).
	ApplyNightlyDecay(ctx context.Context, userID uuid.UUID) error

	// ApplyOverduePenalty applies -3 tree health per overdue task for a single user.
	// overdueCount is the number of PENDING tasks past their end_at deadline.
	ApplyOverduePenalty(ctx context.Context, userID uuid.UUID, overdueCount int) error
}

// userLister can list all user IDs — separate interface per GOV-010 §6.1.
// *repositories.UserRepository satisfies this implicitly.
type userLister interface {
	ListAllUserIDs(ctx context.Context) ([]uuid.UUID, error)
}

// overdueCounter can count overdue tasks per user — separate interface per GOV-010 §6.1.
// *taskRepository satisfies this implicitly.
type overdueCounter interface {
	CountOverdueForUser(ctx context.Context, userID uuid.UUID) (int, error)
}

// GamificationNightlyJob runs at 00:30 UTC every day.
//
// For each registered user it:
//  1. Applies streak reset + tree-health decay (ApplyNightlyDecay)
//  2. Counts that user's PENDING overdue tasks
//  3. Applies the overdue tree-health penalty (ApplyOverduePenalty)
//
// Per-user errors are logged and skipped — one user failure must NOT block others.
// This aligns with GOV-004 §2: no swallowed errors; all logged at ERROR level.
// No os.Exit or log.Fatal inside Run() — per SPR-007-BE Architect audit checklist.
type GamificationNightlyJob struct {
	gamifSvc GamificationServicer
	users    userLister
	tasks    overdueCounter
}

// NewGamificationNightlyJob creates a GamificationNightlyJob.
func NewGamificationNightlyJob(
	gamifSvc GamificationServicer,
	users userLister,
	tasks overdueCounter,
) *GamificationNightlyJob {
	return &GamificationNightlyJob{
		gamifSvc: gamifSvc,
		users:    users,
		tasks:    tasks,
	}
}

// Run is called by the gocron scheduler at 00:30 UTC.
// It fans-out gamification nightly operations across all users.
func (j *GamificationNightlyJob) Run() {
	ctx := context.Background()

	userIDs, err := j.users.ListAllUserIDs(ctx)
	if err != nil {
		slog.ErrorContext(ctx, "gamification_nightly: failed to list users", "error", err)
		return
	}

	slog.InfoContext(ctx, "gamification_nightly: starting", "user_count", len(userIDs))

	var decayErr, penaltyErr int
	for _, userID := range userIDs {
		// ── Step 1: nightly decay (streak reset + tree health) ──────────────────
		if err := j.gamifSvc.ApplyNightlyDecay(ctx, userID); err != nil {
			slog.ErrorContext(ctx, "gamification_nightly: decay failed",
				"user_id", userID.String(),
				"error", err,
			)
			decayErr++
			// Do NOT return — continue to penalty even if decay errors.
		}

		// ── Step 2: count overdue tasks ──────────────────────────────────────────
		overdueCount, err := j.tasks.CountOverdueForUser(ctx, userID)
		if err != nil {
			slog.ErrorContext(ctx, "gamification_nightly: overdue count failed",
				"user_id", userID.String(),
				"error", err,
			)
			penaltyErr++
			continue // cannot compute penalty without the count
		}

		if overdueCount == 0 {
			continue // no penalty to apply
		}

		// ── Step 3: apply overdue penalty ────────────────────────────────────────
		if err := j.gamifSvc.ApplyOverduePenalty(ctx, userID, overdueCount); err != nil {
			slog.ErrorContext(ctx, "gamification_nightly: penalty failed",
				"user_id", userID.String(),
				"overdue_count", overdueCount,
				"error", err,
			)
			penaltyErr++
		}
	}

	slog.InfoContext(ctx, "gamification_nightly: complete",
		"user_count", len(userIDs),
		"decay_errors", decayErr,
		"penalty_errors", penaltyErr,
	)
}
# CI coverage gate: 40% MVP threshold (services+jobs). Target 70% in SPR-008-HRD.
