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
// mockGamifStateRepo — satisfies repositories.GamificationStateReader
// The mock intentionally mutates the same struct pointer to validate the snapshot fix.
// ────────────────────────────────────────────────────────────────────────────

type mockGamifStateRepo struct {
	state            *repositories.GamificationState
	updateErr        error
	graceUsedAtCalls int
	nightlyDecayCalls  int
	treeHealthCalls  int
}

func (m *mockGamifStateRepo) GetByUserID(_ context.Context, _ uuid.UUID) (*repositories.GamificationState, error) {
	if m.state == nil {
		return nil, repositories.ErrNotFound
	}
	return m.state, nil
}

func (m *mockGamifStateRepo) UpdateOnComplete(_ context.Context, _ uuid.UUID, newStreak int, lastActive time.Time) (*repositories.GamificationState, error) {
	if m.updateErr != nil {
		return nil, m.updateErr
	}
	if m.state == nil {
		return nil, repositories.ErrNotFound
	}
	// Mutate same pointer — validates snapshot fix
	m.state.StreakCount = int32(newStreak)
	m.state.LastActiveDate = &lastActive
	m.state.HasCompletedFirstTask = true
	newHealth := int(m.state.TreeHealthScore) + 5
	if newHealth > 100 {
		newHealth = 100
	}
	m.state.TreeHealthScore = int32(newHealth)
	return m.state, nil
}

func (m *mockGamifStateRepo) UpdateGraceUsedAt(_ context.Context, _ uuid.UUID, _ time.Time) error {
	m.graceUsedAtCalls++
	return nil
}

func (m *mockGamifStateRepo) UpdateNightlyDecay(_ context.Context, _ uuid.UUID, newStreak, newHealth int) error {
	m.nightlyDecayCalls++
	if m.state != nil {
		m.state.StreakCount = int32(newStreak)
		m.state.TreeHealthScore = int32(newHealth)
	}
	return nil
}

func (m *mockGamifStateRepo) UpdateTreeHealth(_ context.Context, _ uuid.UUID, newHealth int) error {
	m.treeHealthCalls++
	if m.state != nil {
		m.state.TreeHealthScore = int32(newHealth)
	}
	return nil
}

// Create satisfies the updated GamificationStateReader interface.
// Returns a zeroed GamificationState to simulate lazy seeding in tests.
func (m *mockGamifStateRepo) Create(_ context.Context, userID uuid.UUID) (*repositories.GamificationState, error) {
	seeded := &repositories.GamificationState{
		UserID:          userID,
		TreeHealthScore: 50,
		SpriteType:      "sprite_a",
		TreeType:        "tree_a",
	}
	m.state = seeded
	return seeded, nil
}

// UpdateCompanion satisfies the updated GamificationStateReader interface.
func (m *mockGamifStateRepo) UpdateCompanion(_ context.Context, _ uuid.UUID, spriteType, treeType string) (*repositories.GamificationState, error) {
	if m.state != nil {
		m.state.SpriteType = spriteType
		m.state.TreeType = treeType
	}
	return m.state, nil
}

// ────────────────────────────────────────────────────────────────────────────
// mockBadgeRepo — satisfies repositories.BadgeRepository
// ────────────────────────────────────────────────────────────────────────────

type mockBadgeRepo struct {
	awarded         map[string]bool // badge_id → already awarded?
	taskCountToday  int
}

func newMockBadgeRepo() *mockBadgeRepo {
	return &mockBadgeRepo{awarded: make(map[string]bool)}
}

func (m *mockBadgeRepo) TryAward(_ context.Context, _ uuid.UUID, badgeID string) (bool, error) {
	if m.awarded[badgeID] {
		return false, nil // already awarded — ON CONFLICT DO NOTHING behaviour
	}
	m.awarded[badgeID] = true
	return true, nil
}

func (m *mockBadgeRepo) GetUserBadges(_ context.Context, _ uuid.UUID) ([]*repositories.UserBadge, error) {
	var result []*repositories.UserBadge
	for id := range m.awarded {
		result = append(result, &repositories.UserBadge{BadgeID: id, EarnedAt: time.Now()})
	}
	return result, nil
}

func (m *mockBadgeRepo) GetAllBadges(_ context.Context) ([]*repositories.BadgeCatalogEntry, error) {
	// Return a representative subset for test purposes
	return []*repositories.BadgeCatalogEntry{
		{ID: "FIRST_NIBBLE", Name: "First Nibble", Emoji: "🌱", TriggerType: "FIRST_TASK", Description: "-"},
		{ID: "STREAK_7", Name: "Week Warrior", Emoji: "🔥", TriggerType: "STREAK_MILESTONE", Description: "-"},
	}, nil
}

func (m *mockBadgeRepo) CountTasksCompletedToday(_ context.Context, _ uuid.UUID) (int, error) {
	return m.taskCountToday, nil
}

// ────────────────────────────────────────────────────────────────────────────
// Helpers
// ────────────────────────────────────────────────────────────────────────────

func newSvc(state *repositories.GamificationState) (services.GamificationService, *mockGamifStateRepo, *mockBadgeRepo) {
	repo := &mockGamifStateRepo{state: state}
	badges := newMockBadgeRepo()
	svc := services.NewGamificationService(repo, badges)
	return svc, repo, badges
}

// ────────────────────────────────────────────────────────────────────────────
// Grace Day Tests
// ────────────────────────────────────────────────────────────────────────────

func TestGamif_GraceAvailable_StreakPreserved(t *testing.T) {
	// Day missed, grace never used → streak preserved via grace
	twoDaysAgo := time.Now().UTC().AddDate(0, 0, -2).Truncate(24 * time.Hour)
	userID := uuid.New()
	state := &repositories.GamificationState{
		ID:                    uuid.New(),
		UserID:                userID,
		StreakCount:           5,
		LastActiveDate:        &twoDaysAgo, // missed 1 day
		HasCompletedFirstTask: true,
		TreeHealthScore:       50,
		GraceUsedAt:           nil, // grace never used
	}
	svc, _, _ := newSvc(state)

	delta, err := svc.OnTaskCompleted(context.Background(), userID)

	require.NoError(t, err)
	assert.Equal(t, 5, delta.StreakCount, "streak must be preserved when grace is available")
	assert.True(t, delta.GraceActive, "grace_active must be true")
}

func TestGamif_GraceUsed3DaysAgo_StreakReset(t *testing.T) {
	// Grace was used 3 days ago (within 7-day window) → no grace, streak resets to 1
	threeDaysAgo := time.Now().UTC().AddDate(0, 0, -3).Truncate(24 * time.Hour)
	twoDaysAgo := time.Now().UTC().AddDate(0, 0, -2).Truncate(24 * time.Hour)
	userID := uuid.New()
	state := &repositories.GamificationState{
		ID:                    uuid.New(),
		UserID:                userID,
		StreakCount:           8,
		LastActiveDate:        &twoDaysAgo,
		HasCompletedFirstTask: true,
		TreeHealthScore:       50,
		GraceUsedAt:           &threeDaysAgo,
	}
	svc, _, _ := newSvc(state)

	delta, err := svc.OnTaskCompleted(context.Background(), userID)

	require.NoError(t, err)
	assert.Equal(t, 1, delta.StreakCount, "streak must reset to 1 when grace is exhausted in 7-day window")
	assert.False(t, delta.GraceActive)
}

func TestGamif_GraceUsed8DaysAgo_GraceAvailableAgain(t *testing.T) {
	// Grace was used 8 days ago (outside 7-day window) → grace is available again
	eightDaysAgo := time.Now().UTC().AddDate(0, 0, -8).Truncate(24 * time.Hour)
	twoDaysAgo := time.Now().UTC().AddDate(0, 0, -2).Truncate(24 * time.Hour)
	userID := uuid.New()
	state := &repositories.GamificationState{
		ID:                    uuid.New(),
		UserID:                userID,
		StreakCount:           10,
		LastActiveDate:        &twoDaysAgo,
		HasCompletedFirstTask: true,
		TreeHealthScore:       60,
		GraceUsedAt:           &eightDaysAgo, // outside 7-day window → grace refreshed
	}
	svc, _, _ := newSvc(state)

	delta, err := svc.OnTaskCompleted(context.Background(), userID)

	require.NoError(t, err)
	assert.Equal(t, 10, delta.StreakCount, "streak preserved when grace window has reset")
	assert.True(t, delta.GraceActive)
}

// ────────────────────────────────────────────────────────────────────────────
// Badge Engine Tests
// ────────────────────────────────────────────────────────────────────────────

func TestGamif_FirstCompletion_AwardsFirstNibble(t *testing.T) {
	userID := uuid.New()
	state := &repositories.GamificationState{
		ID:                    uuid.New(),
		UserID:                userID,
		StreakCount:           0,
		HasCompletedFirstTask: false,
		TreeHealthScore:       50,
	}
	svc, _, _ := newSvc(state)

	delta, err := svc.OnTaskCompleted(context.Background(), userID)

	require.NoError(t, err)
	require.Len(t, delta.BadgesAwarded, 1)
	assert.Equal(t, "FIRST_NIBBLE", delta.BadgesAwarded[0].ID)
}

func TestGamif_Streak7_AwardsOnce(t *testing.T) {
	yesterday := time.Now().UTC().AddDate(0, 0, -1).Truncate(24 * time.Hour)
	userID := uuid.New()
	state := &repositories.GamificationState{
		ID:                    uuid.New(),
		UserID:                userID,
		StreakCount:           6, // will become 7
		LastActiveDate:        &yesterday,
		HasCompletedFirstTask: true,
		TreeHealthScore:       50,
	}
	svc, _, badges := newSvc(state)

	// First call — should award STREAK_7
	delta, err := svc.OnTaskCompleted(context.Background(), userID)
	require.NoError(t, err)
	assert.Equal(t, 7, delta.StreakCount)

	// Verify badge awarded
	hasStreak7 := false
	for _, b := range delta.BadgesAwarded {
		if b.ID == "STREAK_7" {
			hasStreak7 = true
		}
	}
	assert.True(t, hasStreak7, "STREAK_7 must be awarded on first reach")
	assert.True(t, badges.awarded["STREAK_7"], "badge must be in repo")

	// Second call on same streak level — streak already 7 in mock, trying again
	// TryAward should return false (already awarded), so badge not in delta
	delta2, err := svc.OnTaskCompleted(context.Background(), userID)
	require.NoError(t, err)
	for _, b := range delta2.BadgesAwarded {
		assert.NotEqual(t, "STREAK_7", b.ID, "STREAK_7 must NOT be awarded twice")
	}
}

func TestGamif_Overachiever_10TasksInDay(t *testing.T) {
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
	_, repo, badges := newSvc(state)
	badges.taskCountToday = 10 // 10 tasks today triggers OVERACHIEVER
	svc := services.NewGamificationService(repo, badges)

	delta, err := svc.OnTaskCompleted(context.Background(), userID)

	require.NoError(t, err)
	hasOverachiever := false
	for _, b := range delta.BadgesAwarded {
		if b.ID == "OVERACHIEVER" {
			hasOverachiever = true
		}
	}
	assert.True(t, hasOverachiever, "OVERACHIEVER badge must be awarded at 10 completions")
}

// ────────────────────────────────────────────────────────────────────────────
// WELCOME State Tests
// ────────────────────────────────────────────────────────────────────────────

func TestGamif_WelcomeState_NoDecayOnMissedDay(t *testing.T) {
	// WELCOME state: has_completed_first_task=false → no penalty on missed day
	// ApplyNightlyDecay should be a no-op
	userID := uuid.New()
	state := &repositories.GamificationState{
		ID:                    uuid.New(),
		UserID:                userID,
		StreakCount:           0,
		HasCompletedFirstTask: false, // WELCOME state
		TreeHealthScore:       50,
	}
	repo := &mockGamifStateRepo{state: state}
	svc := services.NewGamificationService(repo, newMockBadgeRepo())

	err := svc.ApplyNightlyDecay(context.Background(), userID)

	require.NoError(t, err)
	assert.Equal(t, 0, repo.nightlyDecayCalls, "WELCOME state: nightly decay must not be applied")
	assert.Equal(t, int32(50), state.TreeHealthScore, "tree health must be unchanged in WELCOME state")
}

// ────────────────────────────────────────────────────────────────────────────
// Overdue Penalty Test
// ────────────────────────────────────────────────────────────────────────────

func TestGamif_OverduePenalty_NegativeThreePerTask(t *testing.T) {
	userID := uuid.New()
	state := &repositories.GamificationState{
		ID:                    uuid.New(),
		UserID:                userID,
		StreakCount:           5,
		HasCompletedFirstTask: true,
		TreeHealthScore:       50,
	}
	repo := &mockGamifStateRepo{state: state}
	svc := services.NewGamificationService(repo, newMockBadgeRepo())

	err := svc.ApplyOverduePenalty(context.Background(), userID, 3) // 3 overdue tasks

	require.NoError(t, err)
	assert.Equal(t, 1, repo.treeHealthCalls, "UpdateTreeHealth must be called once")
	// 50 - (3 * 3) = 41
	assert.Equal(t, int32(41), state.TreeHealthScore, "tree health must reflect -3 per overdue task")
}

func TestGamif_OverduePenalty_WelcomeGuard(t *testing.T) {
	// WELCOME state must skip overdue penalty
	userID := uuid.New()
	state := &repositories.GamificationState{
		ID:                    uuid.New(),
		UserID:                userID,
		HasCompletedFirstTask: false,
		TreeHealthScore:       50,
	}
	repo := &mockGamifStateRepo{state: state}
	svc := services.NewGamificationService(repo, newMockBadgeRepo())

	err := svc.ApplyOverduePenalty(context.Background(), userID, 5)

	require.NoError(t, err)
	assert.Equal(t, 0, repo.treeHealthCalls, "WELCOME state: overdue penalty must not be applied")
}
