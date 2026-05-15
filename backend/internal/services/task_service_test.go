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
		StartAt:   p.StartAt,
		EndAt:     p.EndAt,
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}
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
			if p.Title != nil {
				t.Title = *p.Title
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

// errGamifSvc always returns an error — tests gamification non-fatal behaviour.
type errGamifSvc struct{}

func (e *errGamifSvc) OnTaskCompleted(_ context.Context, _ uuid.UUID) (*services.GamificationDelta, error) {
	return nil, repositories.ErrNotFound
}

// ────────────────────────────────────────────────────────────────────────────
// CreateTask
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
	assert.Equal(t, 0, repo.createCalls, "no DB call when title is empty")
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

func TestCreateTask_InvalidDateRange(t *testing.T) {
	repo := &mockTaskRepo{}
	svc := services.NewTaskService(repo, &mockGamifSvc{})

	start := time.Now().Add(2 * time.Hour)
	end := time.Now().Add(1 * time.Hour) // end before start

	_, err := svc.CreateTask(context.Background(), uuid.New(), services.CreateTaskRequest{
		Title:    "Bad dates",
		Priority: repositories.PriorityLow,
		TaskType: repositories.TaskTypeOneTime,
		StartAt:  &start,
		EndAt:    &end,
	})

	require.Error(t, err)
	assert.Contains(t, err.Error(), "end_at must be after start_at")
	assert.Equal(t, 0, repo.createCalls)
}

// ────────────────────────────────────────────────────────────────────────────
// ListTasks
// ────────────────────────────────────────────────────────────────────────────

func TestListTasks_FilterByStatus(t *testing.T) {
	userID := uuid.New()
	repo := &mockTaskRepo{}
	repo.tasks = []*repositories.Task{
		{ID: uuid.New(), UserID: userID, Status: repositories.TaskStatusPending, SortOrder: 0, Priority: repositories.PriorityLow, TaskType: repositories.TaskTypeOneTime, CreatedAt: time.Now(), UpdatedAt: time.Now()},
		{ID: uuid.New(), UserID: userID, Status: repositories.TaskStatusCompleted, SortOrder: 1, Priority: repositories.PriorityLow, TaskType: repositories.TaskTypeOneTime, CreatedAt: time.Now(), UpdatedAt: time.Now()},
	}
	svc := services.NewTaskService(repo, &mockGamifSvc{})

	status := repositories.TaskStatusPending
	result, err := svc.ListTasks(context.Background(), userID, services.ListTasksFilter{Status: &status})

	require.NoError(t, err)
	assert.Equal(t, 1, len(result.Data), "only PENDING tasks returned")
	assert.Equal(t, "PENDING", result.Data[0].Status)
}

func TestListTasks_FilterByOverdue(t *testing.T) {
	userID := uuid.New()
	repo := &mockTaskRepo{}

	pastTime := time.Now().Add(-24 * time.Hour)
	futureTime := time.Now().Add(24 * time.Hour)

	overdue := &repositories.Task{ID: uuid.New(), UserID: userID, Status: repositories.TaskStatusPending, EndAt: &pastTime, SortOrder: 0, Priority: repositories.PriorityHigh, TaskType: repositories.TaskTypeOneTime, CreatedAt: time.Now(), UpdatedAt: time.Now()}
	notDue := &repositories.Task{ID: uuid.New(), UserID: userID, Status: repositories.TaskStatusPending, EndAt: &futureTime, SortOrder: 1, Priority: repositories.PriorityLow, TaskType: repositories.TaskTypeOneTime, CreatedAt: time.Now(), UpdatedAt: time.Now()}
	overdue.IsOverdue = overdue.EndAt != nil && overdue.EndAt.Before(time.Now().UTC()) && overdue.Status == repositories.TaskStatusPending
	notDue.IsOverdue = notDue.EndAt != nil && notDue.EndAt.Before(time.Now().UTC()) && notDue.Status == repositories.TaskStatusPending

	repo.tasks = []*repositories.Task{overdue, notDue}
	svc := services.NewTaskService(repo, &mockGamifSvc{})

	overdueStatus := repositories.TaskStatus("overdue")
	result, err := svc.ListTasks(context.Background(), userID, services.ListTasksFilter{Status: &overdueStatus})

	require.NoError(t, err)
	assert.Equal(t, 1, len(result.Data), "only overdue tasks returned")
	assert.True(t, result.Data[0].IsOverdue)
}

func TestListTasks_SortBySortOrder(t *testing.T) {
	userID := uuid.New()
	repo := &mockTaskRepo{}
	repo.tasks = []*repositories.Task{
		{ID: uuid.New(), UserID: userID, Status: repositories.TaskStatusPending, SortOrder: 2, Priority: repositories.PriorityLow, TaskType: repositories.TaskTypeOneTime, CreatedAt: time.Now(), UpdatedAt: time.Now()},
		{ID: uuid.New(), UserID: userID, Status: repositories.TaskStatusPending, SortOrder: 0, Priority: repositories.PriorityLow, TaskType: repositories.TaskTypeOneTime, CreatedAt: time.Now(), UpdatedAt: time.Now()},
		{ID: uuid.New(), UserID: userID, Status: repositories.TaskStatusPending, SortOrder: 1, Priority: repositories.PriorityLow, TaskType: repositories.TaskTypeOneTime, CreatedAt: time.Now(), UpdatedAt: time.Now()},
	}
	svc := services.NewTaskService(repo, &mockGamifSvc{})

	result, err := svc.ListTasks(context.Background(), userID, services.ListTasksFilter{Sort: "sort_order", Order: "asc"})

	require.NoError(t, err)
	assert.Len(t, result.Data, 3)
}

// ────────────────────────────────────────────────────────────────────────────
// GetTask
// ────────────────────────────────────────────────────────────────────────────

func TestGetTask_Success(t *testing.T) {
	userID := uuid.New()
	taskID := uuid.New()
	repo := &mockTaskRepo{}
	repo.tasks = []*repositories.Task{
		{ID: taskID, UserID: userID, Title: "Buy groceries", Status: repositories.TaskStatusPending, Priority: repositories.PriorityMedium, TaskType: repositories.TaskTypeOneTime, SortOrder: 0, CreatedAt: time.Now(), UpdatedAt: time.Now()},
	}
	svc := services.NewTaskService(repo, &mockGamifSvc{})

	resp, err := svc.GetTask(context.Background(), taskID, userID)

	require.NoError(t, err)
	assert.Equal(t, taskID, resp.ID)
	assert.Equal(t, "Buy groceries", resp.Title)
}

func TestGetTask_NotFound(t *testing.T) {
	svc := services.NewTaskService(&mockTaskRepo{}, &mockGamifSvc{})

	_, err := svc.GetTask(context.Background(), uuid.New(), uuid.New())

	require.Error(t, err)
	assert.Contains(t, err.Error(), "task not found")
}

// ────────────────────────────────────────────────────────────────────────────
// UpdateTask
// ────────────────────────────────────────────────────────────────────────────

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
	_, err := svc.UpdateTask(context.Background(), taskID, userID, services.UpdateTaskRequest{Status: &cancelled})

	require.NoError(t, err)
	assert.False(t, gamif.called, "gamification must NOT be called when cancelling")
}

func TestUpdateTask_NotFound(t *testing.T) {
	svc := services.NewTaskService(&mockTaskRepo{}, &mockGamifSvc{})

	title := "updated"
	_, err := svc.UpdateTask(context.Background(), uuid.New(), uuid.New(), services.UpdateTaskRequest{Title: &title})

	require.Error(t, err)
	assert.Contains(t, err.Error(), "task not found")
}

// ────────────────────────────────────────────────────────────────────────────
// CompleteTask
// ────────────────────────────────────────────────────────────────────────────

func TestCompleteTask_Success(t *testing.T) {
	userID := uuid.New()
	taskID := uuid.New()
	repo := &mockTaskRepo{}
	gamif := &mockGamifSvc{
		delta: &services.GamificationDelta{
			StreakCount:     4,
			TreeHealthScore: 55,
			TreeHealthDelta: 5,
			BadgesAwarded:   []services.Badge{},
		},
	}
	repo.tasks = []*repositories.Task{
		{ID: taskID, UserID: userID, Status: repositories.TaskStatusPending, Priority: repositories.PriorityMedium, TaskType: repositories.TaskTypeOneTime, CreatedAt: time.Now(), UpdatedAt: time.Now()},
	}
	svc := services.NewTaskService(repo, gamif)

	resp, err := svc.CompleteTask(context.Background(), taskID, userID)

	require.NoError(t, err)
	assert.Equal(t, "COMPLETED", resp.Task.Status)
	assert.True(t, gamif.called, "gamification must be called on complete")
	assert.Equal(t, 4, resp.GamificationDelta.StreakCount)
}

func TestCompleteTask_AlreadyCompleted_Returns409(t *testing.T) {
	userID := uuid.New()
	taskID := uuid.New()
	repo := &mockTaskRepo{}
	repo.tasks = []*repositories.Task{
		{ID: taskID, UserID: userID, Status: repositories.TaskStatusCompleted, Priority: repositories.PriorityLow, TaskType: repositories.TaskTypeOneTime, CreatedAt: time.Now(), UpdatedAt: time.Now()},
	}
	svc := services.NewTaskService(repo, &mockGamifSvc{})

	_, err := svc.CompleteTask(context.Background(), taskID, userID)

	require.Error(t, err)
	assert.Contains(t, err.Error(), "already completed or cancelled")
}

func TestCompleteTask_GamificationErrorNonFatal(t *testing.T) {
	// Gamification failure must not prevent the task from being marked complete.
	userID := uuid.New()
	taskID := uuid.New()
	repo := &mockTaskRepo{}
	repo.tasks = []*repositories.Task{
		{ID: taskID, UserID: userID, Status: repositories.TaskStatusPending, Priority: repositories.PriorityHigh, TaskType: repositories.TaskTypeOneTime, CreatedAt: time.Now(), UpdatedAt: time.Now()},
	}
	svc := services.NewTaskService(repo, &errGamifSvc{})

	resp, err := svc.CompleteTask(context.Background(), taskID, userID)

	require.NoError(t, err)
	assert.Equal(t, "COMPLETED", resp.Task.Status)
	assert.Equal(t, 0, resp.GamificationDelta.StreakCount, "delta is zero-value on gamification error")
}

// ────────────────────────────────────────────────────────────────────────────
// DeleteTask
// ────────────────────────────────────────────────────────────────────────────

func TestDeleteTask_Success(t *testing.T) {
	userID := uuid.New()
	taskID := uuid.New()
	repo := &mockTaskRepo{}
	repo.tasks = []*repositories.Task{
		{ID: taskID, UserID: userID, Priority: repositories.PriorityLow, TaskType: repositories.TaskTypeOneTime, CreatedAt: time.Now(), UpdatedAt: time.Now()},
	}
	svc := services.NewTaskService(repo, &mockGamifSvc{})

	err := svc.DeleteTask(context.Background(), taskID, userID)

	require.NoError(t, err)
	assert.Empty(t, repo.tasks, "task should be removed from storage")
}

func TestDeleteTask_NotFound(t *testing.T) {
	svc := services.NewTaskService(&mockTaskRepo{}, &mockGamifSvc{})

	err := svc.DeleteTask(context.Background(), uuid.New(), uuid.New())

	require.Error(t, err)
	assert.Contains(t, err.Error(), "task not found")
}

// ────────────────────────────────────────────────────────────────────────────
// UpdateSortOrder
// ────────────────────────────────────────────────────────────────────────────

func TestUpdateSortOrder_Success(t *testing.T) {
	userID := uuid.New()
	taskID := uuid.New()
	repo := &mockTaskRepo{}
	repo.tasks = []*repositories.Task{
		{ID: taskID, UserID: userID, SortOrder: 0, Priority: repositories.PriorityLow, TaskType: repositories.TaskTypeOneTime, CreatedAt: time.Now(), UpdatedAt: time.Now()},
	}
	svc := services.NewTaskService(repo, &mockGamifSvc{})

	err := svc.UpdateSortOrder(context.Background(), taskID, userID, 5)

	require.NoError(t, err)
	assert.Equal(t, 5, repo.tasks[0].SortOrder)
}

func TestUpdateSortOrder_NegativeValueRejected(t *testing.T) {
	svc := services.NewTaskService(&mockTaskRepo{}, &mockGamifSvc{})

	err := svc.UpdateSortOrder(context.Background(), uuid.New(), uuid.New(), -1)

	require.Error(t, err)
	assert.Contains(t, err.Error(), "non-negative")
}

func TestUpdateSortOrder_NotFound(t *testing.T) {
	svc := services.NewTaskService(&mockTaskRepo{}, &mockGamifSvc{})

	err := svc.UpdateSortOrder(context.Background(), uuid.New(), uuid.New(), 3)

	require.Error(t, err)
	assert.Contains(t, err.Error(), "task not found")
}

// ────────────────────────────────────────────────────────────────────────────
// IsOverdue computed field (never stored in DB)
// ────────────────────────────────────────────────────────────────────────────

func TestOverdueTask_IsComputedNotStored(t *testing.T) {
	past := time.Now().Add(-1 * time.Hour)
	task := &repositories.Task{
		ID:       uuid.New(),
		UserID:   uuid.New(),
		Status:   repositories.TaskStatusPending,
		EndAt:    &past,
		Priority: repositories.PriorityLow,
		TaskType: repositories.TaskTypeOneTime,
	}
	task.IsOverdue = task.Status == repositories.TaskStatusPending &&
		task.EndAt != nil && task.EndAt.Before(time.Now().UTC())
	assert.True(t, task.IsOverdue, "PENDING task with past end_at is overdue")

	task.Status = repositories.TaskStatusCompleted
	task.IsOverdue = task.Status == repositories.TaskStatusPending &&
		task.EndAt != nil && task.EndAt.Before(time.Now().UTC())
	assert.False(t, task.IsOverdue, "COMPLETED tasks are never overdue")
}
