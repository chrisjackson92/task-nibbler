package services

import (
	"context"
	"time"

	"github.com/chrisjackson92/task-nibbler/backend/internal/repositories"
	"github.com/google/uuid"
)

// ────────────────────────────────────────────────────────────────────────────
// Badge catalog (static — not stored, just checked against)
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
	StreakCount       int     `json:"streak_count"`
	TreeHealthScore   int     `json:"tree_health_score"`
	TreeHealthDelta   int     `json:"tree_health_delta"`
	GraceActive       bool    `json:"grace_active"`
	BadgesAwarded     []Badge `json:"badges_awarded"`
}

// ────────────────────────────────────────────────────────────────────────────
// Interface
// ────────────────────────────────────────────────────────────────────────────

// GamificationService handles all streak, tree health, and badge logic.
type GamificationService interface {
	OnTaskCompleted(ctx context.Context, userID uuid.UUID) (*GamificationDelta, error)
}

// ────────────────────────────────────────────────────────────────────────────
// Implementation
// ────────────────────────────────────────────────────────────────────────────

type gamificationService struct {
	repo *repositories.GamificationRepository
}

// NewGamificationService creates a GamificationService backed by the repo.
func NewGamificationService(repo *repositories.GamificationRepository) GamificationService {
	return &gamificationService{repo: repo}
}

// OnTaskCompleted applies gamification state changes when any task is completed.
// Logic:
//  1. Load current state
//  2. Increment streak if last_active_date != today UTC
//  3. Persist updated state (tree_health +5 capped at 100 is done in the DB)
//  4. Evaluate instant badges: FIRST_NIBBLE, STREAK_7, STREAK_14, STREAK_30
//  5. Return delta block per CON-002 §3 schema
func (s *gamificationService) OnTaskCompleted(ctx context.Context, userID uuid.UUID) (*GamificationDelta, error) {
	gs, err := s.repo.GetByUserID(ctx, userID)
	if err != nil {
		return nil, err
	}

	todayUTC := time.Now().UTC().Truncate(24 * time.Hour)
	prevHealth := int(gs.TreeHealthScore)

	// Calculate new streak
	newStreak := int(gs.StreakCount)
	if gs.LastActiveDate == nil || gs.LastActiveDate.UTC().Truncate(24*time.Hour).Before(todayUTC) {
		newStreak++
	}
	// If already completed today, streak stays the same (idempotent)

	// Persist update
	updated, err := s.repo.UpdateOnComplete(ctx, userID, newStreak, todayUTC)
	if err != nil {
		return nil, err
	}

	newHealth := int(updated.TreeHealthScore)
	healthDelta := newHealth - prevHealth

	// Evaluate instant badges
	badges := evaluateBadges(updated, gs)

	return &GamificationDelta{
		StreakCount:     newStreak,
		TreeHealthScore: newHealth,
		TreeHealthDelta: healthDelta,
		GraceActive:     false, // grace day logic deferred to SPR-004-BE
		BadgesAwarded:   badges,
	}, nil
}

// evaluateBadges checks which instant badges are newly unlocked by this completion.
// Only badges that were NOT previously earned are returned.
func evaluateBadges(updated, prev *repositories.GamificationState) []Badge {
	var awarded []Badge

	// FIRST_NIBBLE — first task ever completed
	if !prev.HasCompletedFirstTask {
		awarded = append(awarded, Badge{
			ID:          "FIRST_NIBBLE",
			Name:        "First Nibble",
			Emoji:       "🌱",
			Description: "You completed your first task! Your tree is beginning to grow.",
		})
	}

	streak := int(updated.StreakCount)

	// STREAK_7
	if streak >= 7 && int(prev.StreakCount) < 7 {
		awarded = append(awarded, Badge{
			ID:          "STREAK_7",
			Name:        "Week Warrior",
			Emoji:       "🔥",
			Description: "You maintained a 7-day streak! Your tree is starting to grow!",
		})
	}

	// STREAK_14
	if streak >= 14 && int(prev.StreakCount) < 14 {
		awarded = append(awarded, Badge{
			ID:          "STREAK_14",
			Name:        "Fortnight Fighter",
			Emoji:       "⚡",
			Description: "Two weeks of consistency. Your tree is thriving!",
		})
	}

	// STREAK_30
	if streak >= 30 && int(prev.StreakCount) < 30 {
		awarded = append(awarded, Badge{
			ID:          "STREAK_30",
			Name:        "Monthly Master",
			Emoji:       "🏆",
			Description: "30 days straight. You are unstoppable!",
		})
	}

	if awarded == nil {
		awarded = []Badge{} // return empty slice, not nil, so JSON serialises as []
	}
	return awarded
}
