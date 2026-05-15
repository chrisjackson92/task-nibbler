package services

import (
	"context"
	"time"

	"github.com/chrisjackson92/task-nibbler/backend/internal/repositories"
	"github.com/google/uuid"
)

// ────────────────────────────────────────────────────────────────────────────
// Badge catalog (static — not stored in DB for this sprint)
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
	repo repositories.GamificationStateReader
}

// NewGamificationService creates a GamificationService.
// repo must satisfy repositories.GamificationStateReader (satisfied by *repositories.GamificationRepository).
// Using the interface makes the service testable without a real pgx pool (B-058).
func NewGamificationService(repo repositories.GamificationStateReader) GamificationService {
	return &gamificationService{repo: repo}
}

// OnTaskCompleted applies gamification state changes when any task is completed.
// Logic (SPR-002-BE partial scope — grace day + full badge engine in SPR-004-BE):
//  1. Load current state
//  2. Snapshot prev scalar fields BEFORE UpdateOnComplete (repo may return the same pointer)
//  3. Increment streak if last_active_date != today UTC
//  4. Persist updated state (tree_health +5 capped at 100 done in DB via LEAST)
//  5. Evaluate instant badges against snapshotted prev values
//  6. Return delta block per CON-002 §3 schema
func (s *gamificationService) OnTaskCompleted(ctx context.Context, userID uuid.UUID) (*GamificationDelta, error) {
	gs, err := s.repo.GetByUserID(ctx, userID)
	if err != nil {
		return nil, err
	}

	todayUTC := time.Now().UTC().Truncate(24 * time.Hour)
	prevHealth := int(gs.TreeHealthScore)

	// --- Snapshot scalar prev values BEFORE UpdateOnComplete ---
	// The repository mock (and some production paths) may mutate the same struct
	// pointer that GetByUserID returned. Reading gs.StreakCount after UpdateOnComplete
	// would give the already-incremented value, breaking badge threshold detection.
	prevStreak := int(gs.StreakCount)
	prevHasCompletedFirst := gs.HasCompletedFirstTask

	// Calculate new streak (idempotent: same day = no increment)
	newStreak := prevStreak
	if gs.LastActiveDate == nil || gs.LastActiveDate.UTC().Truncate(24*time.Hour).Before(todayUTC) {
		newStreak++
	}

	// Persist update — DB handles LEAST(tree_health_score + 5, 100)
	updated, err := s.repo.UpdateOnComplete(ctx, userID, newStreak, todayUTC)
	if err != nil {
		return nil, err
	}

	newHealth := int(updated.TreeHealthScore)
	healthDelta := newHealth - prevHealth

	// Evaluate instant badges using snapshotted prev values (not gs, which may be mutated)
	badges := evaluateBadges(updated, prevStreak, prevHasCompletedFirst)

	return &GamificationDelta{
		StreakCount:     newStreak,
		TreeHealthScore: newHealth,
		TreeHealthDelta: healthDelta,
		GraceActive:     false, // grace day logic in SPR-004-BE
		BadgesAwarded:   badges,
	}, nil
}

// evaluateBadges checks which instant badges are newly unlocked by this completion.
// prevStreak and prevHasCompletedFirst are scalar snapshots taken before UpdateOnComplete,
// ensuring correct threshold detection even when the repo returns the same pointer.
func evaluateBadges(updated *repositories.GamificationState, prevStreak int, prevHasCompletedFirst bool) []Badge {
	var awarded []Badge

	// FIRST_NIBBLE — first task ever completed
	if !prevHasCompletedFirst {
		awarded = append(awarded, Badge{
			ID:          "FIRST_NIBBLE",
			Name:        "First Nibble",
			Emoji:       "🌱",
			Description: "You completed your first task! Your tree is beginning to grow.",
		})
	}

	streak := int(updated.StreakCount)

	// STREAK_7
	if streak >= 7 && prevStreak < 7 {
		awarded = append(awarded, Badge{
			ID:          "STREAK_7",
			Name:        "Week Warrior",
			Emoji:       "🔥",
			Description: "You maintained a 7-day streak! Your tree is starting to grow!",
		})
	}

	// STREAK_14
	if streak >= 14 && prevStreak < 14 {
		awarded = append(awarded, Badge{
			ID:          "STREAK_14",
			Name:        "Fortnight Fighter",
			Emoji:       "⚡",
			Description: "Two weeks of consistency. Your tree is thriving!",
		})
	}

	// STREAK_30
	if streak >= 30 && prevStreak < 30 {
		awarded = append(awarded, Badge{
			ID:          "STREAK_30",
			Name:        "Monthly Master",
			Emoji:       "🏆",
			Description: "30 days straight. You are unstoppable!",
		})
	}

	if awarded == nil {
		awarded = []Badge{} // never return nil — JSON must serialize as []
	}
	return awarded
}
