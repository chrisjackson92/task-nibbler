package services_test

import (
	"context"
	"testing"
	"time"

	"github.com/chrisjackson92/task-nibbler/backend/internal/apierr"
	"github.com/chrisjackson92/task-nibbler/backend/internal/repositories"
	"github.com/chrisjackson92/task-nibbler/backend/internal/services"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// ────────────────────────────────────────────────────────────────────────────
// Mock implementations
// ────────────────────────────────────────────────────────────────────────────

// mockRuleRepo implements RecurringRuleRepository in memory.
type mockRuleRepo struct {
	rules map[uuid.UUID]*repositories.RecurringRule
}

func newMockRuleRepo() *mockRuleRepo {
	return &mockRuleRepo{rules: make(map[uuid.UUID]*repositories.RecurringRule)}
}

func (m *mockRuleRepo) Create(_ context.Context, userID uuid.UUID, title, rrule string) (*repositories.RecurringRule, error) {
	rule := &repositories.RecurringRule{
		ID:        uuid.New(),
		UserID:    userID,
		Title:     title,
		RRule:     rrule,
		IsActive:  true,
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}
	m.rules[rule.ID] = rule
	return rule, nil
}

func (m *mockRuleRepo) GetByID(_ context.Context, id uuid.UUID) (*repositories.RecurringRule, error) {
	r, ok := m.rules[id]
	if !ok {
		return nil, repositories.ErrNotFound
	}
	return r, nil
}

func (m *mockRuleRepo) ListActive(_ context.Context) ([]*repositories.RecurringRule, error) {
	var result []*repositories.RecurringRule
	for _, r := range m.rules {
		if r.IsActive {
			result = append(result, r)
		}
	}
	return result, nil
}

func (m *mockRuleRepo) Update(_ context.Context, id uuid.UUID, rrule string) error {
	r, ok := m.rules[id]
	if !ok {
		return repositories.ErrNotFound
	}
	r.RRule = rrule
	return nil
}

func (m *mockRuleRepo) Deactivate(_ context.Context, id uuid.UUID) error {
	r, ok := m.rules[id]
	if !ok {
		return repositories.ErrNotFound
	}
	r.IsActive = false
	return nil
}

// mockRecurringTaskRepo extends the existing mockTaskRepo with the two new methods.
// Re-implements only what RecurringService needs.
type mockRecurringTaskRepo struct {
	tasks               map[uuid.UUID]*repositories.Task
	deletedFutureCalled bool
	deletedFutureFrom   time.Time
	deletedFutureRule   uuid.UUID
}

func newMockRecurringTaskRepo() *mockRecurringTaskRepo {
	return &mockRecurringTaskRepo{tasks: make(map[uuid.UUID]*repositories.Task)}
}

func (m *mockRecurringTaskRepo) Create(_ context.Context, p repositories.CreateTaskParams) (*repositories.Task, error) {
	t := &repositories.Task{
		ID:              uuid.New(),
		UserID:          p.UserID,
		RecurringRuleID: p.RecurringRuleID,
		Title:           p.Title,
		Priority:        p.Priority,
		TaskType:        p.TaskType,
		Status:          repositories.TaskStatusPending,
		SortOrder:       p.SortOrder,
		StartAt:         p.StartAt,
		EndAt:           p.EndAt,
		CreatedAt:       time.Now(),
		UpdatedAt:       time.Now(),
	}
	m.tasks[t.ID] = t
	return t, nil
}

func (m *mockRecurringTaskRepo) GetByID(_ context.Context, id, _ uuid.UUID) (*repositories.Task, error) {
	t, ok := m.tasks[id]
	if !ok {
		return nil, repositories.ErrNotFound
	}
	return t, nil
}

func (m *mockRecurringTaskRepo) List(_ context.Context, _ uuid.UUID, _ repositories.ListTasksFilter) (*repositories.TaskPage, error) {
	return &repositories.TaskPage{}, nil
}

func (m *mockRecurringTaskRepo) Update(_ context.Context, id, _ uuid.UUID, p repositories.UpdateTaskParams) (*repositories.Task, error) {
	t, ok := m.tasks[id]
	if !ok {
		return nil, repositories.ErrNotFound
	}
	if p.SetIsDetached {
		t.IsDetached = true
	}
	if p.Title != nil {
		t.Title = *p.Title
	}
	return t, nil
}

func (m *mockRecurringTaskRepo) Delete(_ context.Context, id, _ uuid.UUID) error {
	if _, ok := m.tasks[id]; !ok {
		return repositories.ErrNotFound
	}
	delete(m.tasks, id)
	return nil
}

func (m *mockRecurringTaskRepo) Complete(_ context.Context, _, _ uuid.UUID) (*repositories.Task, error) {
	return nil, nil
}

func (m *mockRecurringTaskRepo) UpdateSortOrder(_ context.Context, _, _ uuid.UUID, _ int) error {
	return nil
}

func (m *mockRecurringTaskRepo) GetMaxSortOrder(_ context.Context, _ uuid.UUID) (int, error) {
	return 0, nil
}

func (m *mockRecurringTaskRepo) CreateIfNotExists(_ context.Context, p repositories.CreateTaskParams) (*repositories.Task, error) {
	// Check if a task with the same rule + date already exists
	if p.RecurringRuleID != nil && p.StartAt != nil {
		startDate := p.StartAt.Truncate(24 * time.Hour)
		for _, t := range m.tasks {
			if t.RecurringRuleID != nil &&
				*t.RecurringRuleID == *p.RecurringRuleID &&
				t.StartAt != nil &&
				t.StartAt.Truncate(24*time.Hour).Equal(startDate) &&
				!t.IsDetached {
				return nil, nil // already exists — idempotent
			}
		}
	}
	return m.Create(context.Background(), p)
}

func (m *mockRecurringTaskRepo) DeleteFuturePending(_ context.Context, ruleID uuid.UUID, fromDate time.Time) error {
	m.deletedFutureCalled = true
	m.deletedFutureRule = ruleID
	m.deletedFutureFrom = fromDate
	for id, t := range m.tasks {
		if t.RecurringRuleID != nil &&
			*t.RecurringRuleID == ruleID &&
			t.Status == repositories.TaskStatusPending &&
			!t.IsDetached &&
			t.StartAt != nil &&
			t.StartAt.After(fromDate) { // strictly after — anchor task not deleted
			delete(m.tasks, id)
		}
	}
	return nil
}

func (m *mockRecurringTaskRepo) CountOverdueForUser(_ context.Context, _ uuid.UUID) (int, error) {
	return 0, nil
}

// ────────────────────────────────────────────────────────────────────────────
// Tests — RecurringService
// ────────────────────────────────────────────────────────────────────────────

func TestCreateRecurring_ValidRRule_CreatesRuleAndTask(t *testing.T) {
	taskRepo := newMockRecurringTaskRepo()
	ruleRepo := newMockRuleRepo()
	svc := services.NewRecurringService(taskRepo, ruleRepo)

	resp, err := svc.CreateRecurring(context.Background(), uuid.New(), services.CreateRecurringRequest{
		CreateTaskRequest: services.CreateTaskRequest{
			Title:    "Daily standup",
			Priority: repositories.PriorityMedium,
			TaskType: repositories.TaskTypeRecurring,
		},
		RRule: "FREQ=DAILY;INTERVAL=1",
	})

	require.NoError(t, err)
	require.NotNil(t, resp)
	assert.Equal(t, "Daily standup", resp.Title)
	assert.Len(t, ruleRepo.rules, 1, "exactly one rule must be created")
	assert.Len(t, taskRepo.tasks, 1, "exactly one task instance must be created")
}

func TestCreateRecurring_InvalidRRule_Returns422(t *testing.T) {
	svc := services.NewRecurringService(newMockRecurringTaskRepo(), newMockRuleRepo())

	_, err := svc.CreateRecurring(context.Background(), uuid.New(), services.CreateRecurringRequest{
		CreateTaskRequest: services.CreateTaskRequest{
			Title:    "Bad task",
			Priority: repositories.PriorityLow,
			TaskType: repositories.TaskTypeRecurring,
		},
		RRule: "NOT_A_VALID_RRULE",
	})

	require.Error(t, err)
	var apiErr *apierr.APIError
	require.ErrorAs(t, err, &apiErr)
	assert.Equal(t, "INVALID_RRULE", apiErr.Code)
}

func TestUpdateScoped_ThisOnly_SetsIsDetached(t *testing.T) {
	taskRepo := newMockRecurringTaskRepo()
	ruleRepo := newMockRuleRepo()
	svc := services.NewRecurringService(taskRepo, ruleRepo)

	userID := uuid.New()
	ruleID := uuid.New()

	// Seed a recurring task
	task := &repositories.Task{
		ID:              uuid.New(),
		UserID:          userID,
		RecurringRuleID: &ruleID,
		Title:           "Morning run",
		Priority:        repositories.PriorityLow,
		TaskType:        repositories.TaskTypeRecurring,
		Status:          repositories.TaskStatusPending,
		IsDetached:      false,
		CreatedAt:       time.Now(),
		UpdatedAt:       time.Now(),
	}
	taskRepo.tasks[task.ID] = task

	newTitle := "Afternoon run"
	resp, err := svc.UpdateScoped(context.Background(), task.ID, userID, services.UpdateScopedRequest{
		Scope: services.ScopeThisOnly,
		UpdateTaskRequest: services.UpdateTaskRequest{
			Title: &newTitle,
		},
	})

	require.NoError(t, err)
	require.NotNil(t, resp)
	assert.True(t, taskRepo.tasks[task.ID].IsDetached, "is_detached must be TRUE after scope=this_only")
	assert.Equal(t, "Afternoon run", taskRepo.tasks[task.ID].Title)
}

func TestUpdateScoped_ScopeAbsent_Returns422(t *testing.T) {
	svc := services.NewRecurringService(newMockRecurringTaskRepo(), newMockRuleRepo())

	_, err := svc.UpdateScoped(context.Background(), uuid.New(), uuid.New(), services.UpdateScopedRequest{
		Scope: "", // absent
	})

	require.Error(t, err)
	var apiErr *apierr.APIError
	require.ErrorAs(t, err, &apiErr)
	assert.Equal(t, "VALIDATION_ERROR", apiErr.Code)
}

func TestUpdateScoped_ThisAndFuture_DeletesFuturePending(t *testing.T) {
	taskRepo := newMockRecurringTaskRepo()
	ruleRepo := newMockRuleRepo()
	svc := services.NewRecurringService(taskRepo, ruleRepo)

	userID := uuid.New()

	// Create a rule
	rule, _ := ruleRepo.Create(context.Background(), userID, "Daily", "FREQ=DAILY;INTERVAL=1")

	// Seed the anchor task (today)
	now := time.Now().UTC()
	anchorTask := &repositories.Task{
		ID:              uuid.New(),
		UserID:          userID,
		RecurringRuleID: &rule.ID,
		Title:           "Daily",
		Priority:        repositories.PriorityMedium,
		TaskType:        repositories.TaskTypeRecurring,
		Status:          repositories.TaskStatusPending,
		StartAt:         &now,
		CreatedAt:       now,
		UpdatedAt:       now,
	}
	taskRepo.tasks[anchorTask.ID] = anchorTask

	// Seed a future PENDING instance
	tomorrow := now.AddDate(0, 0, 1)
	futureTask := &repositories.Task{
		ID:              uuid.New(),
		UserID:          userID,
		RecurringRuleID: &rule.ID,
		Title:           "Daily",
		Priority:        repositories.PriorityMedium,
		TaskType:        repositories.TaskTypeRecurring,
		Status:          repositories.TaskStatusPending,
		StartAt:         &tomorrow,
		CreatedAt:       now,
		UpdatedAt:       now,
	}
	taskRepo.tasks[futureTask.ID] = futureTask

	newRRule := "FREQ=DAILY;INTERVAL=2"
	_, err := svc.UpdateScoped(context.Background(), anchorTask.ID, userID, services.UpdateScopedRequest{
		Scope: services.ScopeThisAndFuture,
		RRule: newRRule,
		UpdateTaskRequest: services.UpdateTaskRequest{
			Title: nil,
		},
	})

	require.NoError(t, err)
	assert.True(t, taskRepo.deletedFutureCalled, "DeleteFuturePending must be called for scope=this_and_future")
	// Future task must be gone
	_, futureStillExists := taskRepo.tasks[futureTask.ID]
	assert.False(t, futureStillExists, "future PENDING instance must be deleted")
	// Rule must be updated
	assert.Equal(t, newRRule, ruleRepo.rules[rule.ID].RRule)
}

func TestDeleteScoped_ThisOnly_DeletesOnlyOneTask(t *testing.T) {
	taskRepo := newMockRecurringTaskRepo()
	ruleRepo := newMockRuleRepo()
	svc := services.NewRecurringService(taskRepo, ruleRepo)

	userID := uuid.New()
	ruleID := uuid.New()

	task1 := &repositories.Task{
		ID: uuid.New(), UserID: userID, RecurringRuleID: &ruleID,
		Status: repositories.TaskStatusPending, CreatedAt: time.Now(), UpdatedAt: time.Now(),
	}
	task2 := &repositories.Task{
		ID: uuid.New(), UserID: userID, RecurringRuleID: &ruleID,
		Status: repositories.TaskStatusPending, CreatedAt: time.Now(), UpdatedAt: time.Now(),
	}
	taskRepo.tasks[task1.ID] = task1
	taskRepo.tasks[task2.ID] = task2

	err := svc.DeleteScoped(context.Background(), task1.ID, userID, services.ScopeThisOnly)

	require.NoError(t, err)
	_, task1Gone := taskRepo.tasks[task1.ID]
	assert.False(t, task1Gone, "task1 must be deleted")
	_, task2Still := taskRepo.tasks[task2.ID]
	assert.True(t, task2Still, "task2 must NOT be deleted for scope=this_only")
}

func TestDeleteScoped_ThisAndFuture_DeactivatesRuleAndDeletesFuture(t *testing.T) {
	taskRepo := newMockRecurringTaskRepo()
	ruleRepo := newMockRuleRepo()
	svc := services.NewRecurringService(taskRepo, ruleRepo)

	userID := uuid.New()
	rule, _ := ruleRepo.Create(context.Background(), userID, "Standup", "FREQ=DAILY")

	now := time.Now().UTC()
	anchor := &repositories.Task{
		ID: uuid.New(), UserID: userID, RecurringRuleID: &rule.ID,
		Status: repositories.TaskStatusPending, StartAt: &now,
		CreatedAt: now, UpdatedAt: now,
	}
	future := time.Now().Add(24 * time.Hour)
	futurePending := &repositories.Task{
		ID: uuid.New(), UserID: userID, RecurringRuleID: &rule.ID,
		Status: repositories.TaskStatusPending, StartAt: &future,
		CreatedAt: now, UpdatedAt: now,
	}
	taskRepo.tasks[anchor.ID] = anchor
	taskRepo.tasks[futurePending.ID] = futurePending

	err := svc.DeleteScoped(context.Background(), anchor.ID, userID, services.ScopeThisAndFuture)

	require.NoError(t, err)
	assert.False(t, ruleRepo.rules[rule.ID].IsActive, "rule must be is_active=FALSE")
	assert.True(t, taskRepo.deletedFutureCalled, "DeleteFuturePending must be called")
	_, futureGone := taskRepo.tasks[futurePending.ID]
	assert.False(t, futureGone, "future PENDING instance must be deleted")
	_, anchorGone := taskRepo.tasks[anchor.ID]
	assert.False(t, anchorGone, "anchor task must also be deleted for scope=this_and_future (Finding #3)")
}

func TestDeleteScoped_ScopeAbsent_Returns422(t *testing.T) {
	svc := services.NewRecurringService(newMockRecurringTaskRepo(), newMockRuleRepo())

	err := svc.DeleteScoped(context.Background(), uuid.New(), uuid.New(), "")

	require.Error(t, err)
	var apiErr *apierr.APIError
	require.ErrorAs(t, err, &apiErr)
	assert.Equal(t, "VALIDATION_ERROR", apiErr.Code)
}
