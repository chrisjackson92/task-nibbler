package jobs_test

import (
	"context"
	"errors"
	"testing"

	"github.com/chrisjackson92/task-nibbler/backend/internal/jobs"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
)

// ────────────────────────────────────────────────────────────────────────────
// Mocks
// ────────────────────────────────────────────────────────────────────────────

type mockGamifSvc struct {
	decayErr   error
	penaltyErr error
	decayCalls []uuid.UUID
	penCalls   []uuid.UUID
}

func (m *mockGamifSvc) ApplyNightlyDecay(_ context.Context, userID uuid.UUID) error {
	m.decayCalls = append(m.decayCalls, userID)
	return m.decayErr
}

func (m *mockGamifSvc) ApplyOverduePenalty(_ context.Context, userID uuid.UUID, _ int) error {
	m.penCalls = append(m.penCalls, userID)
	return m.penaltyErr
}

type mockUserLister struct {
	ids []uuid.UUID
	err error
}

func (m *mockUserLister) ListAllUserIDs(_ context.Context) ([]uuid.UUID, error) {
	return m.ids, m.err
}

type mockOverdueCounter struct {
	count int
	err   error
}

func (m *mockOverdueCounter) CountOverdueForUser(_ context.Context, _ uuid.UUID) (int, error) {
	return m.count, m.err
}

// ────────────────────────────────────────────────────────────────────────────
// Tests
// ────────────────────────────────────────────────────────────────────────────

// TestGamificationNightlyJob_Run_Success verifies that both decay and penalty
// are called for each user when all operations succeed.
func TestGamificationNightlyJob_Run_Success(t *testing.T) {
	u1, u2 := uuid.New(), uuid.New()
	gamifSvc := &mockGamifSvc{}
	users := &mockUserLister{ids: []uuid.UUID{u1, u2}}
	tasks := &mockOverdueCounter{count: 2} // 2 overdue tasks per user

	job := jobs.NewGamificationNightlyJob(gamifSvc, users, tasks)
	job.Run()

	assert.ElementsMatch(t, []uuid.UUID{u1, u2}, gamifSvc.decayCalls,
		"ApplyNightlyDecay must be called for every user")
	assert.ElementsMatch(t, []uuid.UUID{u1, u2}, gamifSvc.penCalls,
		"ApplyOverduePenalty must be called for every user that has overdue tasks")
}

// TestGamificationNightlyJob_Run_NoOverdue verifies that penalty is NOT called
// when a user has zero overdue tasks (no unnecessary DB writes).
func TestGamificationNightlyJob_Run_NoOverdue(t *testing.T) {
	userID := uuid.New()
	gamifSvc := &mockGamifSvc{}
	users := &mockUserLister{ids: []uuid.UUID{userID}}
	tasks := &mockOverdueCounter{count: 0} // no overdue tasks

	job := jobs.NewGamificationNightlyJob(gamifSvc, users, tasks)
	job.Run()

	assert.Equal(t, 1, len(gamifSvc.decayCalls), "decay must be called")
	assert.Empty(t, gamifSvc.penCalls, "penalty must NOT be called when overdueCount == 0")
}

// TestGamificationNightlyJob_Run_DecayError_PenaltyStillRuns verifies that a
// decay error for one user does NOT prevent penalty from running for that user
// or decay from running for subsequent users.
func TestGamificationNightlyJob_Run_DecayError_PenaltyStillRuns(t *testing.T) {
	u1, u2 := uuid.New(), uuid.New()
	gamifSvc := &mockGamifSvc{
		decayErr: errors.New("db error"),
	}
	users := &mockUserLister{ids: []uuid.UUID{u1, u2}}
	tasks := &mockOverdueCounter{count: 1}

	job := jobs.NewGamificationNightlyJob(gamifSvc, users, tasks)
	job.Run() // must not panic

	// Decay was attempted for both users despite the error
	assert.ElementsMatch(t, []uuid.UUID{u1, u2}, gamifSvc.decayCalls,
		"decay must be attempted for all users even after individual errors")
	// Penalty still runs for both (decay error ≠ early return)
	assert.ElementsMatch(t, []uuid.UUID{u1, u2}, gamifSvc.penCalls,
		"penalty must still run for all users even when decay errors")
}

// TestGamificationNightlyJob_Run_PenaltyError_DoesNotAbort verifies that a
// penalty error for one user does not prevent processing of subsequent users.
func TestGamificationNightlyJob_Run_PenaltyError_DoesNotAbort(t *testing.T) {
	u1, u2 := uuid.New(), uuid.New()
	gamifSvc := &mockGamifSvc{
		penaltyErr: errors.New("penalty db error"),
	}
	users := &mockUserLister{ids: []uuid.UUID{u1, u2}}
	tasks := &mockOverdueCounter{count: 3}

	job := jobs.NewGamificationNightlyJob(gamifSvc, users, tasks)
	job.Run() // must not panic

	// Both users had decay applied
	assert.ElementsMatch(t, []uuid.UUID{u1, u2}, gamifSvc.decayCalls)
	// Both users had penalty attempted (error doesn't stop u2)
	assert.ElementsMatch(t, []uuid.UUID{u1, u2}, gamifSvc.penCalls)
}

// TestGamificationNightlyJob_Run_UserListError verifies that a failure to list
// users causes an early return (nothing else runs — nothing to iterate).
func TestGamificationNightlyJob_Run_UserListError(t *testing.T) {
	gamifSvc := &mockGamifSvc{}
	users := &mockUserLister{err: errors.New("db unavailable")}
	tasks := &mockOverdueCounter{count: 1}

	job := jobs.NewGamificationNightlyJob(gamifSvc, users, tasks)
	job.Run() // must not panic

	assert.Empty(t, gamifSvc.decayCalls, "no users processed when list fails")
	assert.Empty(t, gamifSvc.penCalls, "no penalties applied when list fails")
}
