package jobs

import (
	"context"
	"log/slog"
	"time"

	"github.com/chrisjackson92/task-nibbler/backend/internal/repositories"
	"github.com/google/uuid"
	rrulego "github.com/teambition/rrule-go"
)

// userTzReader is a minimal interface for reading a user's IANA timezone.
// Defined in the consumer package per GOV-010 §6.1 (Finding #2 — AUD-006-BE).
// *repositories.UserRepository satisfies this interface.
type userTzReader interface {
	GetByID(ctx context.Context, id uuid.UUID) (*repositories.User, error)
}

// RecurringExpansionJob expands all active recurring rules for the next 30 days.
// It is idempotent: re-running on the same night creates no duplicate instances
// because CreateIfNotExists uses ON CONFLICT DO NOTHING on uq_recurring_instance.
//
// Registered in main.go: runs nightly at 00:15 UTC (after AttachmentCleanupJob at 00:05).
type RecurringExpansionJob struct {
	ruleRepo repositories.RecurringRuleRepository
	taskRepo repositories.TaskRepository
	userRepo userTzReader // interface — enables in-process testing without a real DB
}

// NewRecurringExpansionJob creates a RecurringExpansionJob.
func NewRecurringExpansionJob(
	ruleRepo repositories.RecurringRuleRepository,
	taskRepo repositories.TaskRepository,
	userRepo userTzReader,
) *RecurringExpansionJob {
	return &RecurringExpansionJob{
		ruleRepo: ruleRepo,
		taskRepo: taskRepo,
		userRepo: userRepo,
	}
}

// Run executes the expansion for all active rules.
// Called by gocron scheduler; also callable directly in tests.
func (j *RecurringExpansionJob) Run(ctx context.Context) {
	rules, err := j.ruleRepo.ListActive(ctx)
	if err != nil {
		slog.ErrorContext(ctx, "recurring_expansion: failed to list active rules", "error", err)
		return
	}

	slog.InfoContext(ctx, "recurring_expansion: starting", "rule_count", len(rules))

	for _, rule := range rules {
		if err := j.expandRule(ctx, rule); err != nil {
			slog.ErrorContext(ctx, "recurring_expansion: failed to expand rule",
				"rule_id", rule.ID.String(),
				"user_id", rule.UserID.String(),
				"error", err,
			)
			// Continue with other rules — one failure must not block the rest
		}
	}

	slog.InfoContext(ctx, "recurring_expansion: complete", "rule_count", len(rules))
}

// expandRule expands a single recurring rule, creating task instances for the next 30 days.
// Timezone-aware: uses user.Timezone to interpret the RRULE (e.g. "9am Eastern" → correct UTC offset).
func (j *RecurringExpansionJob) expandRule(ctx context.Context, rule *repositories.RecurringRule) error {
	// Fetch user to get their stored timezone
	user, err := j.userRepo.GetByID(ctx, rule.UserID)
	if err != nil {
		return err
	}

	// Load the user's IANA timezone location (e.g. "America/New_York").
	// Falls back to UTC if the stored string is missing or invalid.
	loc, err := time.LoadLocation(user.Timezone)
	if err != nil {
		slog.WarnContext(ctx, "recurring_expansion: invalid timezone; falling back to UTC",
			"rule_id", rule.ID.String(),
			"user_id", rule.UserID.String(),
			"timezone", user.Timezone,
		)
		loc = time.UTC
	}

	// Parse the RRULE string
	rSet, err := rrulego.StrToRRuleSet(rule.RRule)
	if err != nil {
		// StrToRRuleSet failed — parse as a plain RFC RRULE string in user's timezone.
		// StrToROptionInLocation automatically sets Dtstart in the given location.
		opt, err2 := rrulego.StrToROptionInLocation(rule.RRule, loc)
		if err2 != nil {
			return err2
		}
		if opt.Dtstart.IsZero() {
			opt.Dtstart = time.Now().In(loc)
		}
		rRule, err3 := rrulego.NewRRule(*opt)
		if err3 != nil {
			return err3
		}
		rSet = &rrulego.Set{}
		rSet.RRule(rRule)
	}

	now := time.Now().UTC()
	horizon := now.AddDate(0, 0, 30)

	occurrences := rSet.Between(now, horizon, true)

	var created, skipped int
	ruleID := rule.ID
	for _, occ := range occurrences {
		startAt := occ.UTC()
		task, err := j.taskRepo.CreateIfNotExists(ctx, repositories.CreateTaskParams{
			UserID:          rule.UserID,
			RecurringRuleID: &ruleID,
			Title:           rule.Title, // sourced from recurring_rules.title (Finding #1 — AUD-006-BE)
			Priority:        repositories.PriorityMedium,
			TaskType:        repositories.TaskTypeRecurring,
			SortOrder:       0,
			StartAt:         &startAt,
		})
		if err != nil {
			return err
		}
		if task == nil {
			skipped++ // ON CONFLICT DO NOTHING — already existed
		} else {
			created++
		}
	}

	slog.InfoContext(ctx, "recurring_expansion: rule expanded",
		"rule_id", rule.ID.String(),
		"user_id", rule.UserID.String(),
		"occurrences", len(occurrences),
		"instances_created", created,
		"instances_skipped", skipped,
	)
	return nil
}
