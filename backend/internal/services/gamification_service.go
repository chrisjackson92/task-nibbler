package services

import (
	"context"
	"errors"
	"time"

	"github.com/chrisjackson92/task-nibbler/backend/internal/repositories"
	"github.com/google/uuid"
)

// ────────────────────────────────────────────────────────────────────────────
// Badge catalog (static shapes for delta response)
// ────────────────────────────────────────────────────────────────────────────

// Badge represents a gamification badge as returned by CON-002 §3.
type Badge struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Emoji       string `json:"emoji"`
	Description string `json:"description"`
}

// GamificationDelta is the response block returned by POST /tasks/:id/complete.
type GamificationDelta struct {
	StreakCount     int     `json:"streak_count"`
	TreeHealthScore int     `json:"tree_health_score"`
	TreeHealthDelta int     `json:"tree_health_delta"`
	GraceActive     bool    `json:"grace_active"`
	BadgesAwarded   []Badge `json:"badges_awarded"`
}

// GamificationStateResponse is the response for GET /gamification/state.
type GamificationStateResponse struct {
	StreakCount             int     `json:"streak_count"`
	LastActiveDate         *string `json:"last_active_date"` // YYYY-MM-DD or null
	GraceActive             bool    `json:"grace_active"`
	HasCompletedFirstTask   bool    `json:"has_completed_first_task"`
	TreeHealthScore         int     `json:"tree_health_score"`
	TreeState               string  `json:"tree_state"`   // THRIVING|HEALTHY|STRUGGLING|WITHERING
	SpriteState             string  `json:"sprite_state"` // WELCOME|HAPPY|NEUTRAL|SAD
	SpriteType              string  `json:"sprite_type"`  // sprite_a|sprite_b
	TreeType                string  `json:"tree_type"`    // tree_a|tree_b
	TotalBadgesEarned       int     `json:"total_badges_earned"`
}

// BadgeListItem is the item shape for GET /gamification/badges.
type BadgeListItem struct {
	ID          string  `json:"id"`
	Name        string  `json:"name"`
	Emoji       string  `json:"emoji"`
	Description string  `json:"description"`
	TriggerType string  `json:"trigger_type"`
	Earned      bool    `json:"earned"`
	EarnedAt    *string `json:"earned_at"` // ISO 8601 or null
}

// ────────────────────────────────────────────────────────────────────────────
// Interface
// ────────────────────────────────────────────────────────────────────────────

// GamificationService handles all streak, tree health, grace day, and badge logic.
type GamificationService interface {
	OnTaskCompleted(ctx context.Context, userID uuid.UUID) (*GamificationDelta, error)
	GetState(ctx context.Context, userID uuid.UUID) (*GamificationStateResponse, error)
	GetBadges(ctx context.Context, userID uuid.UUID) ([]*BadgeListItem, error)
	UpdateCompanion(ctx context.Context, userID uuid.UUID, spriteType, treeType string) (*GamificationStateResponse, error)

	// ApplyNightlyDecay applies zero-completion streak reset + tree health decay.
	// Called by the nightly cron for users who had no completions yesterday.
	// WELCOME guard: if has_completed_first_task=false, skip all penalties.
	ApplyNightlyDecay(ctx context.Context, userID uuid.UUID) error

	// ApplyOverduePenalty applies -3 tree health per overdue task for a user.
	// Called by the nightly cron to penalise outstanding overdue tasks.
	// WELCOME guard: skip if has_completed_first_task=false.
	ApplyOverduePenalty(ctx context.Context, userID uuid.UUID, overdueCount int) error
}

// ────────────────────────────────────────────────────────────────────────────
// Implementation
// ────────────────────────────────────────────────────────────────────────────

type gamificationService struct {
	stateRepo repositories.GamificationStateReader
	badgeRepo repositories.BadgeRepository
}

// NewGamificationService creates a GamificationService.
// stateRepo satisfies repositories.GamificationStateReader (concrete *GamificationRepository).
// badgeRepo satisfies repositories.BadgeRepository.
func NewGamificationService(
	stateRepo repositories.GamificationStateReader,
	badgeRepo repositories.BadgeRepository,
) GamificationService {
	return &gamificationService{stateRepo: stateRepo, badgeRepo: badgeRepo}
}

// OnTaskCompleted applies gamification state changes when any task is completed.
// Per SPR-004-BE spec:
//  1. Load current state
//  2. Snapshot prev scalar fields BEFORE UpdateOnComplete
//  3. Increment streak if last_active_date != today UTC; handle grace day if missed
//  4. Persist updated state (tree_health +5 capped at 100 done in DB via LEAST)
//  5. Evaluate instant badges against pre-mutation snapshots
//  6. Return delta block per CON-002 §3 schema
func (s *gamificationService) OnTaskCompleted(ctx context.Context, userID uuid.UUID) (*GamificationDelta, error) {
	gs, err := s.stateRepo.GetByUserID(ctx, userID)
	if err != nil {
		if !errors.Is(err, repositories.ErrNotFound) {
			return nil, err
		}
		// Lazy seed: registration seed failed non-fatally — create the row now.
		gs, err = s.stateRepo.Create(ctx, userID)
		if err != nil {
			return nil, err
		}
	}

	todayUTC := time.Now().UTC().Truncate(24 * time.Hour)
	prevHealth := int(gs.TreeHealthScore)

	// Snapshot BEFORE any mutation (B-058 fix — same pointer may be returned by UpdateOnComplete)
	prevStreak := int(gs.StreakCount)
	prevHasCompletedFirst := gs.HasCompletedFirstTask

	// Determine new streak
	newStreak := prevStreak
	graceActive := false

	if gs.LastActiveDate == nil {
		// First ever completion: streak starts at 1
		newStreak = 1
	} else {
		lastActiveDay := gs.LastActiveDate.UTC().Truncate(24 * time.Hour)
		daysSinceActive := int(todayUTC.Sub(lastActiveDay).Hours() / 24)

		switch {
		case daysSinceActive == 0:
			// Already active today — idempotent, no streak change
		case daysSinceActive == 1:
			// Consecutive day — increment streak
			newStreak++
		default:
			// Missed at least one day — apply grace day or reset
			newStreak, graceActive = s.applyMissedDay(gs, todayUTC, prevStreak)
		}
	}

	// Persist update — DB handles LEAST(tree_health_score + 5, 100)
	updated, err := s.stateRepo.UpdateOnComplete(ctx, userID, newStreak, todayUTC)
	if err != nil {
		return nil, err
	}

	newHealth := int(updated.TreeHealthScore)
	healthDelta := newHealth - prevHealth

	// Count tasks completed today for OVERACHIEVER badge
	taskCountToday, _ := s.badgeRepo.CountTasksCompletedToday(ctx, userID)

	// Evaluate instant badges using pre-mutation snapshots
	badges, err := s.evaluateInstantBadges(ctx, userID, updated, prevStreak, prevHealth, prevHasCompletedFirst, taskCountToday)
	if err != nil {
		return nil, err
	}

	return &GamificationDelta{
		StreakCount:     newStreak,
		TreeHealthScore: newHealth,
		TreeHealthDelta: healthDelta,
		GraceActive:     graceActive,
		BadgesAwarded:   badges,
	}, nil
}

// applyMissedDay applies grace day or streak reset when daysSinceActive >= 2.
// Grace day rule: 1 grace per 7-day rolling window.
// Returns (newStreak, graceActive).
func (s *gamificationService) applyMissedDay(gs *repositories.GamificationState, todayUTC time.Time, currentStreak int) (int, bool) {
	if !gs.HasCompletedFirstTask {
		// WELCOME state — no penalty
		return currentStreak + 1, false
	}

	graceWindowStart := todayUTC.AddDate(0, 0, -7)
	graceAvailable := gs.GraceUsedAt == nil || gs.GraceUsedAt.Before(graceWindowStart)

	if graceAvailable {
		// Grace: preserve streak + consume grace day (to be saved in UpdateOnComplete)
		return currentStreak, true // grace_used_at updated in UpdateOnComplete if graceActive
	}

	// No grace — reset streak, preserve health (tree health loss is applied by nightly cron)
	return 1, false // streak resets to 1 for today's completion
}

// evaluateInstantBadges evaluates badges that can be awarded immediately on task completion.
// Volume×Streak badges (CONSISTENT_*, PRODUCTIVE_*) are evaluated by nightly cron.
func (s *gamificationService) evaluateInstantBadges(
	ctx context.Context,
	userID uuid.UUID,
	updated *repositories.GamificationState,
	prevStreak int,
	prevHealth int,
	prevHasCompletedFirst bool,
	taskCountToday int,
) ([]Badge, error) {
	newStreak := int(updated.StreakCount)
	newHealth := int(updated.TreeHealthScore)

	// Candidates evaluated on completion (per BLU-002-SD §3)
	type candidate struct {
		badgeID   string
		condition bool
	}
	candidates := []candidate{
		{"FIRST_NIBBLE", !prevHasCompletedFirst},
		{"STREAK_7", newStreak >= 7 && prevStreak < 7},
		{"STREAK_14", newStreak >= 14 && prevStreak < 14},
		{"STREAK_30", newStreak >= 30 && prevStreak < 30},
		{"STREAK_100", newStreak >= 100 && prevStreak < 100},
		{"STREAK_365", newStreak >= 365 && prevStreak < 365},
		{"OVERACHIEVER", taskCountToday >= 10},
		{"TREE_HEALTHY", newHealth >= 50 && prevHealth < 50},
		{"TREE_THRIVING", newHealth >= 75 && prevHealth < 75},
	}

	var awarded []Badge
	for _, c := range candidates {
		if !c.condition {
			continue
		}
		newly, err := s.badgeRepo.TryAward(ctx, userID, c.badgeID)
		if err != nil {
			return nil, err
		}
		if newly {
			// Fetch badge details from catalog to populate the delta response
			b := badgeCatalogEntry(c.badgeID)
			if b != nil {
				awarded = append(awarded, *b)
			}
		}
	}

	if awarded == nil {
		awarded = []Badge{} // always return empty slice, never nil (JSON: [])
	}
	return awarded, nil
}

// GetState returns the full gamification state with computed tree_state and sprite_state.
func (s *gamificationService) GetState(ctx context.Context, userID uuid.UUID) (*GamificationStateResponse, error) {
	gs, err := s.stateRepo.GetByUserID(ctx, userID)
	if err != nil {
		if !errors.Is(err, repositories.ErrNotFound) {
			return nil, err
		}
		// Lazy seed if registration seed failed non-fatally.
		gs, err = s.stateRepo.Create(ctx, userID)
		if err != nil {
			return nil, err
		}
	}

	// Count earned badges
	userBadges, err := s.badgeRepo.GetUserBadges(ctx, userID)
	if err != nil {
		return nil, err
	}

	health := int(gs.TreeHealthScore)
	streak := int(gs.StreakCount)

	// Check if grace is currently active (consumed within last 7 days but within window)
	graceActive := gs.GraceUsedAt != nil &&
		!gs.GraceUsedAt.Before(time.Now().UTC().AddDate(0, 0, -7))

	// Computed: last_active_date as YYYY-MM-DD string
	var lastActiveDateStr *string
	if gs.LastActiveDate != nil {
		s := gs.LastActiveDate.UTC().Format("2006-01-02")
		lastActiveDateStr = &s
	}

	return &GamificationStateResponse{
		StreakCount:           streak,
		LastActiveDate:        lastActiveDateStr,
		GraceActive:           graceActive,
		HasCompletedFirstTask: gs.HasCompletedFirstTask,
		TreeHealthScore:       health,
		TreeState:             computeTreeState(health),
		SpriteState:           computeSpriteState(gs.HasCompletedFirstTask, streak, health),
		SpriteType:            gs.SpriteType,
		TreeType:              gs.TreeType,
		TotalBadgesEarned:     len(userBadges),
	}, nil
}

// UpdateCompanion persists the user's companion selection and returns updated state.
func (s *gamificationService) UpdateCompanion(ctx context.Context, userID uuid.UUID, spriteType, treeType string) (*GamificationStateResponse, error) {
	gs, err := s.stateRepo.UpdateCompanion(ctx, userID, spriteType, treeType)
	if err != nil {
		return nil, err
	}
	health := int(gs.TreeHealthScore)
	streak := int(gs.StreakCount)
	return &GamificationStateResponse{
		StreakCount:           streak,
		GraceActive:           gs.GraceUsedAt != nil,
		HasCompletedFirstTask: gs.HasCompletedFirstTask,
		TreeHealthScore:       health,
		TreeState:             computeTreeState(health),
		SpriteState:           computeSpriteState(gs.HasCompletedFirstTask, streak, health),
		SpriteType:            gs.SpriteType,
		TreeType:              gs.TreeType,
	}, nil
}

// GetBadges returns all 14 catalog badges with earned status for this user.
func (s *gamificationService) GetBadges(ctx context.Context, userID uuid.UUID) ([]*BadgeListItem, error) {
	catalog, err := s.badgeRepo.GetAllBadges(ctx)
	if err != nil {
		return nil, err
	}
	userBadges, err := s.badgeRepo.GetUserBadges(ctx, userID)
	if err != nil {
		return nil, err
	}

	// Build an earned_at map for O(1) lookup
	earnedMap := make(map[string]string, len(userBadges))
	for _, ub := range userBadges {
		t := ub.EarnedAt.UTC().Format(time.RFC3339)
		earnedMap[ub.BadgeID] = t
	}

	result := make([]*BadgeListItem, 0, len(catalog))
	for _, b := range catalog {
		item := &BadgeListItem{
			ID:          b.ID,
			Name:        b.Name,
			Emoji:       b.Emoji,
			Description: b.Description,
			TriggerType: b.TriggerType,
		}
		if earnedAt, ok := earnedMap[b.ID]; ok {
			item.Earned = true
			item.EarnedAt = &earnedAt
		}
		result = append(result, item)
	}
	return result, nil
}

// ApplyNightlyDecay resets streak and deducts -10 tree health for zero-completion days.
// WELCOME guard: no penalties if has_completed_first_task=false.
// Called by the nightly cron for users who had no completions yesterday.
func (s *gamificationService) ApplyNightlyDecay(ctx context.Context, userID uuid.UUID) error {
	gs, err := s.stateRepo.GetByUserID(ctx, userID)
	if err != nil {
		return err
	}
	if !gs.HasCompletedFirstTask {
		return nil // WELCOME state — zero penalties until first task complete (B-051)
	}

	// Apply grace or reset streak + tree health
	todayUTC := time.Now().UTC().Truncate(24 * time.Hour)
	graceWindowStart := todayUTC.AddDate(0, 0, -7)
	graceAvailable := gs.GraceUsedAt == nil || gs.GraceUsedAt.Before(graceWindowStart)

	if graceAvailable {
		// Consume grace — streak is preserved, no health penalty
		return s.stateRepo.UpdateGraceUsedAt(ctx, userID, todayUTC)
	}

	// Reset streak + -10 tree health
	newHealth := max(0, int(gs.TreeHealthScore)-10)
	return s.stateRepo.UpdateNightlyDecay(ctx, userID, 0, newHealth)
}

// ApplyOverduePenalty deducts -3 tree health per overdue task.
// WELCOME guard: skip if has_completed_first_task=false.
// Called by the nightly cron for each user with outstanding overdue tasks.
func (s *gamificationService) ApplyOverduePenalty(ctx context.Context, userID uuid.UUID, overdueCount int) error {
	if overdueCount <= 0 {
		return nil
	}
	gs, err := s.stateRepo.GetByUserID(ctx, userID)
	if err != nil {
		return err
	}
	if !gs.HasCompletedFirstTask {
		return nil // WELCOME guard (B-051)
	}

	penalty := overdueCount * 3
	newHealth := max(0, int(gs.TreeHealthScore)-penalty)
	return s.stateRepo.UpdateTreeHealth(ctx, userID, newHealth)
}

// ────────────────────────────────────────────────────────────────────────────
// Computed fields per CON-002 §5
// ────────────────────────────────────────────────────────────────────────────

func computeTreeState(health int) string {
	switch {
	case health >= 75:
		return "THRIVING"
	case health >= 50:
		return "HEALTHY"
	case health >= 25:
		return "STRUGGLING"
	default:
		return "WITHERING"
	}
}

func computeSpriteState(hasCompletedFirst bool, streak, health int) string {
	if !hasCompletedFirst {
		return "WELCOME"
	}
	if streak >= 1 && health >= 60 {
		return "HAPPY"
	}
	if streak >= 1 && health >= 30 {
		return "NEUTRAL"
	}
	return "SAD"
}

// ────────────────────────────────────────────────────────────────────────────
// Badge catalog lookup (in-memory, avoids DB round-trip for delta response)
// ────────────────────────────────────────────────────────────────────────────

// badgeCatalogEntry returns the in-memory Badge for a known ID.
// This avoids a DB read during the hot path of OnTaskCompleted.
func badgeCatalogEntry(id string) *Badge {
	catalog := map[string]Badge{
		"FIRST_NIBBLE": {ID: "FIRST_NIBBLE", Name: "First Nibble", Emoji: "🌱",
			Description: "You completed your very first task. Every journey starts with a single nibble!"},
		"STREAK_7": {ID: "STREAK_7", Name: "Week Warrior", Emoji: "🔥",
			Description: "You maintained a 7-day streak. Your tree is starting to grow!"},
		"STREAK_14": {ID: "STREAK_14", Name: "Fortnight Fighter", Emoji: "⚡",
			Description: "Two weeks of consistency — your companion is cheering you on!"},
		"STREAK_30": {ID: "STREAK_30", Name: "Monthly Maven", Emoji: "🏆",
			Description: "A full month of showing up. You are unstoppable."},
		"STREAK_100": {ID: "STREAK_100", Name: "Century Club", Emoji: "💯",
			Description: "100 days of consistency. Your tree is magnificent."},
		"STREAK_365": {ID: "STREAK_365", Name: "Unstoppable", Emoji: "🌟",
			Description: "One full year of daily tasking. Legendary."},
		"OVERACHIEVER": {ID: "OVERACHIEVER", Name: "Daily Overachiever", Emoji: "⚡",
			Description: "You completed 10 or more tasks in a single day. Incredible!"},
		"TREE_HEALTHY": {ID: "TREE_HEALTHY", Name: "Sprout", Emoji: "🌿",
			Description: "Your tree reached a healthy state for the first time. Keep it growing!"},
		"TREE_THRIVING": {ID: "TREE_THRIVING", Name: "In Bloom", Emoji: "🌸",
			Description: "Your tree is thriving! Consistent effort has made it flourish."},
	}
	b, ok := catalog[id]
	if !ok {
		return nil
	}
	return &b
}
