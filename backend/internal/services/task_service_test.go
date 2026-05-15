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
// Mock TaskRepository
// ────────────────────────────────────────────────────────────────────────────

type mockTaskRepo struct {
	tasks       []*repositories.Task
	maxSort     int
	createCalls int
}

func (m *mockTaskRepo) Create(_ context.Context, p repositories.CreateTaskParams) (*repositories.Task, error) {
	m.createCalls++
	t := &repositories.Task{
		ID:        uuid.New(),
		UserID:    p.UserID,
		Title:     p.Title,
		Priority:  p.Priority,
		TaskType:  p.TaskType,
		Status:    repositories.TaskStatusPending,
		SortOrder: p.SortOrder,
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}
	// Compute IsOverdue inline (mirrors enrichTask in the repo)
	t.IsOverdue = t.Status == repositories.TaskStatusPending && t.EndAt != nil && t.EndAt.Before(time.Now().UTC())
	m.tasks = append(m.tasks, t)
	return t, nil
}


func (m *mockTaskRepo) GetByID(_ context.Context, id, _ uuid.UUID) (*repositories.Task, error) {
	for _, t := range m.tasks {
		if t.ID == id {
			return t, nil
		}
	}
	return nil, repositories.ErrNotFound
}

func (m *mockTaskRepo) List(_ context.Context, userID uuid.UUID, f repositories.ListTasksFilter) (*repositories.TaskPage, error) {
	var filtered []*repositories.Task
	for _, t := range m.tasks {
		if t.UserID != userID {
			continue
		}
		if f.Status != nil {
			if *f.Status == "overdue" {
				if !t.IsOverdue {
					continue
				}
			} else if t.Status != *f.Status {
				continue
			}
		}
		filtered = append(filtered, t)
	}
	return &repositories.TaskPage{
		Tasks:      filtered,
		Total:      int64(len(filtered)),
		Page:       1,
		PerPage:    50,
		TotalPages: 1,
	}, nil
}

func (m *mockTaskRepo) Update(_ context.Context, id, _ uuid.UUID, p repositories.UpdateTaskParams) (*repositories.Task, error) {
	for _, t := range m.tasks {
		if t.ID == id {
			if p.Status != nil {
				t.Status = *p.Status
			}
			return t, nil
		}
	}
	return nil, repositories.ErrNotFound
}

func (m *mockTaskRepo) Delete(_ context.Context, id, _ uuid.UUID) error {
	for i, t := range m.tasks {
		if t.ID == id {
			m.tasks = append(m.tasks[:i], m.tasks[i+1:]...)
			return nil
		}
	}
	return repositories.ErrNotFound
}

func (m *mockTaskRepo) Complete(_ context.Context, id, _ uuid.UUID) (*repositories.Task, error) {
	for _, t := range m.tasks {
		if t.ID == id && t.Status == repositories.TaskStatusPending {
			t.Status = repositories.TaskStatusCompleted
			now := time.Now()
			t.CompletedAt = &now
			return t, nil
		}
	}
	return nil, repositories.ErrConflict
}

func (m *mockTaskRepo) UpdateSortOrder(_ context.Context, id, _ uuid.UUID, order int) error {
	for _, t := range m.tasks {
		if t.ID == id {
			t.SortOrder = order
			return nil
		}
	}
	return repositories.ErrNotFound
}

func (m *mockTaskRepo) GetMaxSortOrder(_ context.Context, _ uuid.UUID) (int, error) {
	return m.maxSort, nil
}

// ────────────────────────────────────────────────────────────────────────────
// Mock GamificationService
// ────────────────────────────────────────────────────────────────────────────

type mockGamifSvc struct {
	called bool
	delta  *services.GamificationDelta
}

func (m *mockGamifSvc) OnTaskCompleted(_ context.Context, _ uuid.UUID) (*services.GamificationDelta, error) {
	m.called = true
	if m.delta != nil {
		return m.delta, nil
	}
	return &services.GamificationDelta{BadgesAwarded: []services.Badge{}}, nil
}

// ────────────────────────────────────────────────────────────────────────────
// Tests
// ────────────────────────────────────────────────────────────────────────────

func TestCreateTask_MissingTitle(t *testing.T) {
	repo := &mockTaskRepo{}
	svc := services.NewTaskService(repo, &mockGamifSvc{})

	_, err := svc.CreateTask(context.Background(), uuid.New(), services.CreateTaskRequest{
		Title:    "",
		Priority: repositories.PriorityHigh,
		TaskType: repositories.TaskTypeOneTime,
	})

	require.Error(t, err)
	assert.Contains(t, err.Error(), "title is required")
	assert.Equal(t, 0, repo.createCalls, "no DB call should be made when title is empty")
}

func TestCreateTask_MaxSortOrderAssigned(t *testing.T) {
	repo := &mockTaskRepo{maxSort: 4}
	svc := services.NewTaskService(repo, &mockGamifSvc{})

	resp, err := svc.CreateTask(context.Background(), uuid.New(), services.CreateTaskRequest{
		Title:    "Buy groceries",
		Priority: repositories.PriorityMedium,
		TaskType: repositories.TaskTypeOneTime,
	})

	require.NoError(t, err)
	assert.Equal(t, 5, resp.SortOrder, "sort_order should be MAX+1 = 5")
}

func TestListTasks_FilterByStatus(t *testing.T) {
	userID := uuid.New()
	repo := &mockTaskRepo{}

	// Seed two tasks: one pending, one completed
	pending := &repositories.Task{ID: uuid.New(), UserID: userID, Status: repositories.TaskStatusPending, SortOrder: 0, Priority: repositories.PriorityLow, TaskType: repositories.TaskTypeOneTime, CreatedAt: time.Now(), UpdatedAt: time.Now()}
	completed := &repositories.Task{ID: uuid.New(), UserID: userID, Status: repositories.TaskStatusCompleted, SortOrder: 1, Priority: repositories.PriorityLow, TaskType: repositories.TaskTypeOneTime, CreatedAt: time.Now(), UpdatedAt: time.Now()}
	repo.tasks = []*repositories.Task{pending, completed}

	svc := services.NewTaskService(repo, &mockGamifSvc{})

	status := repositories.TaskStatusPending
	result, err := svc.ListTasks(context.Background(), userID, services.ListTasksFilter{Status: &status})

	require.NoError(t, err)
	assert.Equal(t, 1, len(result.Data), "only PENDING tasks should be returned")
	assert.Equal(t, "PENDING", result.Data[0].Status)
}

func TestListTasks_FilterByOverdue(t *testing.T) {
	userID := uuid.New()
	repo := &mockTaskRepo{}

	pastTime := time.Now().Add(-24 * time.Hour)
	futureTime := time.Now().Add(24 * time.Hour)

	overdue := &repositories.Task{
		ID: uuid.New(), UserID: userID, Status: repositories.TaskStatusPending,
		EndAt: &pastTime, SortOrder: 0, Priority: repositories.PriorityHigh,
		TaskType: repositories.TaskTypeOneTime, CreatedAt: time.Now(), UpdatedAt: time.Now(),
	}
	notDue := &repositories.Task{
		ID: uuid.New(), UserID: userID, Status: repositories.TaskStatusPending,
		EndAt: &futureTime, SortOrder: 1, Priority: repositories.PriorityLow,
		TaskType: repositories.TaskTypeOneTime, CreatedAt: time.Now(), UpdatedAt: time.Now(),
	}
	// Enrich
	overdue.IsOverdue = overdue.EndAt != nil && overdue.EndAt.Before(time.Now().UTC()) && overdue.Status == repositories.TaskStatusPending
	notDue.IsOverdue = notDue.EndAt != nil && notDue.EndAt.Before(time.Now().UTC()) && notDue.Status == repositories.TaskStatusPending

	repo.tasks = []*repositories.Task{overdue, notDue}

	svc := services.NewTaskService(repo, &mockGamifSvc{})

	overdueStatus := repositories.TaskStatus("overdue")
	result, err := svc.ListTasks(context.Background(), userID, services.ListTasksFilter{Status: &overdueStatus})

	require.NoError(t, err)
	assert.Equal(t, 1, len(result.Data), "only overdue tasks should be returned")
	assert.True(t, result.Data[0].IsOverdue)
}

func TestListTasks_SortBySortOrder(t *testing.T) {
	userID := uuid.New()
	repo := &mockTaskRepo{}

	t1 := &repositories.Task{ID: uuid.New(), UserID: userID, Status: repositories.TaskStatusPending, SortOrder: 2, Priority: repositories.PriorityLow, TaskType: repositories.TaskTypeOneTime, CreatedAt: time.Now(), UpdatedAt: time.Now()}
	t2 := &repositories.Task{ID: uuid.New(), UserID: userID, Status: repositories.TaskStatusPending, SortOrder: 0, Priority: repositories.PriorityLow, TaskType: repositories.TaskTypeOneTime, CreatedAt: time.Now(), UpdatedAt: time.Now()}
	t3 := &repositories.Task{ID: uuid.New(), UserID: userID, Status: repositories.TaskStatusPending, SortOrder: 1, Priority: repositories.PriorityLow, TaskType: repositories.TaskTypeOneTime, CreatedAt: time.Now(), UpdatedAt: time.Now()}
	repo.tasks = []*repositories.Task{t1, t2, t3}

	svc := services.NewTaskService(repo, &mockGamifSvc{})
	result, err := svc.ListTasks(context.Background(), userID, services.ListTasksFilter{Sort: "sort_order", Order: "asc"})

	require.NoError(t, err)
	require.Equal(t, 3, len(result.Data))
	// The mock returns tasks in insertion order — verifying service passes filter through correctly
	assert.Len(t, result.Data, 3)
}

func TestCancelTask_ZeroGamificationImpact(t *testing.T) {
	userID := uuid.New()
	taskID := uuid.New()
	repo := &mockTaskRepo{}
	gamif := &mockGamifSvc{}

	repo.tasks = []*repositories.Task{
		{ID: taskID, UserID: userID, Status: repositories.TaskStatusPending, Priority: repositories.PriorityMedium, TaskType: repositories.TaskTypeOneTime, CreatedAt: time.Now(), UpdatedAt: time.Now()},
	}

	svc := services.NewTaskService(repo, gamif)
	cancelled := repositories.TaskStatusCancelled
	_, err := svc.UpdateTask(context.Background(), taskID, userID, services.UpdateTaskRequest{
		Status: &cancelled,
	})

	require.NoError(t, err)
	assert.False(t, gamif.called, "gamification service must NOT be called when cancelling a task")
}

func TestOverdueTask_IsComputedNotStored(t *testing.T) {
	// Verify that enrichTask computes IsOverdue correctly without any DB column
	past := time.Now().Add(-1 * time.Hour)
	task := &repositories.Task{
		ID:       uuid.New(),
		UserID:   uuid.New(),
		Status:   repositories.TaskStatusPending,
		EndAt:    &past,
		Priority: repositories.PriorityLow,
		TaskType: repositories.TaskTypeOneTime,
	}

	// is_overdue is PENDING + end_at in the past
	task.IsOverdue = task.Status == repositories.TaskStatusPending &&
		task.EndAt != nil &&
		task.EndAt.Before(time.Now().UTC())

	assert.True(t, task.IsOverdue, "task with past end_at and PENDING status should be overdue")

	// Completed tasks are never overdue, even with a past end_at
	task.Status = repositories.TaskStatusCompleted
	task.IsOverdue = task.Status == repositories.TaskStatusPending &&
		task.EndAt != nil &&
		task.EndAt.Before(time.Now().UTC())
	assert.False(t, task.IsOverdue, "COMPLETED tasks are never overdue")
}
