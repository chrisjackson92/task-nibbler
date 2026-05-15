package services_test

import (
	"context"
	"testing"
	"time"

	"github.com/chrisjackson92/task-nibbler/backend/internal/repositories"
	"github.com/chrisjackson92/task-nibbler/backend/internal/services"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// ────────────────────────────────────────────────────────────────────────────
// mockGamifStateRepo — satisfies repositories.GamificationStateReader.
// Injected into the REAL GamificationService so the production code path
// is exercised, not a fake re-implementation (B-058, AUD-002-BE Finding #3).
// ────────────────────────────────────────────────────────────────────────────

type mockGamifStateRepo struct {
	state *repositories.GamificationState
}

func (m *mockGamifStateRepo) GetByUserID(_ context.Context, _ uuid.UUID) (*repositories.GamificationState, error) {
	if m.state == nil {
		return nil, repositories.ErrNotFound
	}
	return m.state, nil
}

func (m *mockGamifStateRepo) UpdateOnComplete(_ context.Context, _ uuid.UUID, newStreak int, lastActive time.Time) (*repositories.GamificationState, error) {
	if m.state == nil {
		return nil, repositories.ErrNotFound
	}
	// Mutate in-place to simulate the DB returning the same struct.
	// This is intentional: it validates the snapshot fix in gamification_service.go.
	m.state.StreakCount = int32(newStreak)
	m.state.LastActiveDate = &lastActive
	m.state.HasCompletedFirstTask = true
	newScore := m.state.TreeHealthScore + 5
	if newScore > 100 {
		newScore = 100
	}
	m.state.TreeHealthScore = newScore
	return m.state, nil
}

// ────────────────────────────────────────────────────────────────────────────
// Tests — all use services.NewGamificationService (real implementation)
// ────────────────────────────────────────────────────────────────────────────

func TestGamif_OnTaskCompleted_IncrementsStreak(t *testing.T) {
	yesterday := time.Now().UTC().AddDate(0, 0, -1).Truncate(24 * time.Hour)
	userID := uuid.New()
	state := &repositories.GamificationState{
		ID:                    uuid.New(),
		UserID:                userID,
		StreakCount:           3,
		LastActiveDate:        &yesterday,
		HasCompletedFirstTask: true,
		TreeHealthScore:       50,
	}
	svc := services.NewGamificationService(&mockGamifStateRepo{state: state})

	delta, err := svc.OnTaskCompleted(context.Background(), userID)

	require.NoError(t, err)
	assert.Equal(t, 4, delta.StreakCount, "streak should increment from 3 → 4")
	assert.Equal(t, 5, delta.TreeHealthDelta, "tree health delta should be +5")
	assert.Equal(t, 55, delta.TreeHealthScore)
	assert.Empty(t, delta.BadgesAwarded, "no streak badge at 4")
}

func TestGamif_OnTaskCompleted_AwardsFirstNibbleBadge(t *testing.T) {
	userID := uuid.New()
	state := &repositories.GamificationState{
		ID:                    uuid.New(),
		UserID:                userID,
		StreakCount:           0,
		HasCompletedFirstTask: false, // first task ever
		TreeHealthScore:       50,
	}
	svc := services.NewGamificationService(&mockGamifStateRepo{state: state})

	delta, err := svc.OnTaskCompleted(context.Background(), userID)

	require.NoError(t, err)
	require.Len(t, delta.BadgesAwarded, 1, "FIRST_NIBBLE badge must be awarded")
	assert.Equal(t, "FIRST_NIBBLE", delta.BadgesAwarded[0].ID)
}

func TestGamif_OnTaskCompleted_AwardsStreak7Badge(t *testing.T) {
	yesterday := time.Now().UTC().AddDate(0, 0, -1).Truncate(24 * time.Hour)
	userID := uuid.New()
	state := &repositories.GamificationState{
		ID:                    uuid.New(),
		UserID:                userID,
		StreakCount:           6, // completing today → 7
		LastActiveDate:        &yesterday,
		HasCompletedFirstTask: true,
		TreeHealthScore:       50,
	}
	svc := services.NewGamificationService(&mockGamifStateRepo{state: state})

	delta, err := svc.OnTaskCompleted(context.Background(), userID)

	require.NoError(t, err)
	assert.Equal(t, 7, delta.StreakCount)
	require.Len(t, delta.BadgesAwarded, 1, "STREAK_7 badge must be awarded")
	assert.Equal(t, "STREAK_7", delta.BadgesAwarded[0].ID)
}

func TestGamif_OnTaskCompleted_AwardsStreak14Badge(t *testing.T) {
	yesterday := time.Now().UTC().AddDate(0, 0, -1).Truncate(24 * time.Hour)
	userID := uuid.New()
	state := &repositories.GamificationState{
		ID:                    uuid.New(),
		UserID:                userID,
		StreakCount:           13, // → 14
		LastActiveDate:        &yesterday,
		HasCompletedFirstTask: true,
		TreeHealthScore:       60,
	}
	svc := services.NewGamificationService(&mockGamifStateRepo{state: state})

	delta, err := svc.OnTaskCompleted(context.Background(), userID)

	require.NoError(t, err)
	assert.Equal(t, 14, delta.StreakCount)
	require.Len(t, delta.BadgesAwarded, 1, "STREAK_14 badge must be awarded")
	assert.Equal(t, "STREAK_14", delta.BadgesAwarded[0].ID)
}

func TestGamif_OnTaskCompleted_AwardsStreak30Badge(t *testing.T) {
	yesterday := time.Now().UTC().AddDate(0, 0, -1).Truncate(24 * time.Hour)
	userID := uuid.New()
	state := &repositories.GamificationState{
		ID:                    uuid.New(),
		UserID:                userID,
		StreakCount:           29, // → 30
		LastActiveDate:        &yesterday,
		HasCompletedFirstTask: true,
		TreeHealthScore:       80,
	}
	svc := services.NewGamificationService(&mockGamifStateRepo{state: state})

	delta, err := svc.OnTaskCompleted(context.Background(), userID)

	require.NoError(t, err)
	assert.Equal(t, 30, delta.StreakCount)
	require.Len(t, delta.BadgesAwarded, 1, "STREAK_30 badge must be awarded")
	assert.Equal(t, "STREAK_30", delta.BadgesAwarded[0].ID)
}

func TestGamif_OnTaskCompleted_IdempotentSameDay(t *testing.T) {
	today := time.Now().UTC().Truncate(24 * time.Hour)
	userID := uuid.New()
	state := &repositories.GamificationState{
		ID:                    uuid.New(),
		UserID:                userID,
		StreakCount:           5,
		LastActiveDate:        &today, // already active today
		HasCompletedFirstTask: true,
		TreeHealthScore:       50,
	}
	svc := services.NewGamificationService(&mockGamifStateRepo{state: state})

	delta, err := svc.OnTaskCompleted(context.Background(), userID)

	require.NoError(t, err)
	assert.Equal(t, 5, delta.StreakCount, "streak must NOT increment when already active today")
}

func TestGamif_OnTaskCompleted_TreeHealthCappedAt100(t *testing.T) {
	yesterday := time.Now().UTC().AddDate(0, 0, -1).Truncate(24 * time.Hour)
	userID := uuid.New()
	state := &repositories.GamificationState{
		ID:                    uuid.New(),
		UserID:                userID,
		StreakCount:           1,
		LastActiveDate:        &yesterday,
		HasCompletedFirstTask: true,
		TreeHealthScore:       98, // +5 would exceed 100
	}
	svc := services.NewGamificationService(&mockGamifStateRepo{state: state})

	delta, err := svc.OnTaskCompleted(context.Background(), userID)

	require.NoError(t, err)
	assert.Equal(t, 100, delta.TreeHealthScore, "tree health must be capped at 100")
	assert.Equal(t, 2, delta.TreeHealthDelta, "delta reflects actual change: 100-98=2")
}

func TestGamif_OnTaskCompleted_NoStateReturnsError(t *testing.T) {
	repo := &mockGamifStateRepo{state: nil}
	svc := services.NewGamificationService(repo)

	_, err := svc.OnTaskCompleted(context.Background(), uuid.New())

	require.Error(t, err)
}
