package services

import (
	"context"
	"errors"
	"log/slog"
	"time"

	"github.com/chrisjackson92/task-nibbler/backend/internal/apierr"
	"github.com/chrisjackson92/task-nibbler/backend/internal/repositories"
	"github.com/google/uuid"
)

// ────────────────────────────────────────────────────────────────────────────
// Request / Response DTOs
// ────────────────────────────────────────────────────────────────────────────

// CreateTaskRequest holds validated input from the POST /tasks handler.
type CreateTaskRequest struct {
	Title           string
	Description     *string
	Address         *string
	Priority        repositories.Priority
	TaskType        repositories.TaskType
	SortOrder       *int    // nil = assign MAX+1
	StartAt         *time.Time
	EndAt           *time.Time
}

// UpdateTaskRequest holds optional fields for a partial PATCH /tasks/:id.
type UpdateTaskRequest struct {
	Title       *string
	Description *string
	Address     *string
	Priority    *repositories.Priority
	TaskType    *repositories.TaskType
	Status      *repositories.TaskStatus
	SortOrder   *int
	StartAt     *time.Time
	EndAt       *time.Time
}

// ListTasksFilter mirrors query-param filters for GET /tasks.
type ListTasksFilter struct {
	Status   *repositories.TaskStatus
	Priority *repositories.Priority
	Type     *repositories.TaskType
	From     *time.Time
	To       *time.Time
	Search   *string
	Sort     string
	Order    string
	Page     int
	PerPage  int
}

// TaskResponse is the serialisable Task DTO returned to handlers.
type TaskResponse struct {
	ID              uuid.UUID  `json:"id"`
	UserID          uuid.UUID  `json:"user_id"`
	RecurringRuleID *uuid.UUID `json:"recurring_rule_id"`
	Title           string     `json:"title"`
	Description     *string    `json:"description"`
	Address         *string    `json:"address"`
	Priority        string     `json:"priority"`
	TaskType        string     `json:"task_type"`
	Status          string     `json:"status"`
	IsOverdue       bool       `json:"is_overdue"`
	SortOrder       int        `json:"sort_order"`
	IsDetached      bool       `json:"is_detached"`
	StartAt         *time.Time `json:"start_at"`
	EndAt           *time.Time `json:"end_at"`
	CompletedAt     *time.Time `json:"completed_at"`
	CancelledAt     *time.Time `json:"cancelled_at"`
	CreatedAt       time.Time  `json:"created_at"`
	UpdatedAt       time.Time  `json:"updated_at"`
}

// TaskPageResponse is the paginated list response for GET /tasks.
type TaskPageResponse struct {
	Data []TaskResponse `json:"data"`
	Meta struct {
		Total      int64 `json:"total"`
		Page       int   `json:"page"`
		PerPage    int   `json:"per_page"`
		TotalPages int   `json:"total_pages"`
	} `json:"meta"`
}

// CompleteTaskResponse is the response for POST /tasks/:id/complete.
type CompleteTaskResponse struct {
	Task              TaskResponse      `json:"task"`
	GamificationDelta GamificationDelta `json:"gamification_delta"`
}

// ────────────────────────────────────────────────────────────────────────────
// Interface
// ────────────────────────────────────────────────────────────────────────────

// TaskService defines the business logic contract for task operations.
type TaskService interface {
	ListTasks(ctx context.Context, userID uuid.UUID, filter ListTasksFilter) (*TaskPageResponse, error)
	CreateTask(ctx context.Context, userID uuid.UUID, req CreateTaskRequest) (*TaskResponse, error)
	GetTask(ctx context.Context, id, userID uuid.UUID) (*TaskResponse, error)
	UpdateTask(ctx context.Context, id, userID uuid.UUID, req UpdateTaskRequest) (*TaskResponse, error)
	DeleteTask(ctx context.Context, id, userID uuid.UUID) error
	CompleteTask(ctx context.Context, id, userID uuid.UUID) (*CompleteTaskResponse, error)
	UpdateSortOrder(ctx context.Context, id, userID uuid.UUID, sortOrder int) error
}

// ────────────────────────────────────────────────────────────────────────────
// Implementation
// ────────────────────────────────────────────────────────────────────────────

type taskService struct {
	tasks  repositories.TaskRepository
	gamify GamificationService
}

// NewTaskService creates a TaskService with the required dependencies.
func NewTaskService(tasks repositories.TaskRepository, gamify GamificationService) TaskService {
	return &taskService{tasks: tasks, gamify: gamify}
}

func (s *taskService) ListTasks(ctx context.Context, userID uuid.UUID, f ListTasksFilter) (*TaskPageResponse, error) {
	page, err := s.tasks.List(ctx, userID, repositories.ListTasksFilter{
		Status:   f.Status,
		Priority: f.Priority,
		Type:     f.Type,
		From:     f.From,
		To:       f.To,
		Search:   f.Search,
		Sort:     f.Sort,
		Order:    f.Order,
		Page:     f.Page,
		PerPage:  f.PerPage,
	})
	if err != nil {
		return nil, err
	}

	resp := &TaskPageResponse{}
	resp.Meta.Total = page.Total
	resp.Meta.Page = page.Page
	resp.Meta.PerPage = page.PerPage
	resp.Meta.TotalPages = page.TotalPages
	resp.Data = make([]TaskResponse, 0, len(page.Tasks))
	for _, t := range page.Tasks {
		resp.Data = append(resp.Data, toTaskResponse(t))
	}
	return resp, nil
}

func (s *taskService) CreateTask(ctx context.Context, userID uuid.UUID, req CreateTaskRequest) (*TaskResponse, error) {
	// Validate
	if req.Title == "" {
		return nil, apierr.New(422, "VALIDATION_ERROR", "title is required")
	}
	if req.EndAt != nil && req.StartAt != nil && req.EndAt.Before(*req.StartAt) {
		return nil, apierr.New(422, "INVALID_DATE_RANGE", "end_at must be after start_at")
	}

	// Assign sort_order: use MAX+1 unless caller specifies
	sortOrder := 0
	if req.SortOrder != nil {
		sortOrder = *req.SortOrder
	} else {
		max, err := s.tasks.GetMaxSortOrder(ctx, userID)
		if err != nil {
			return nil, err
		}
		sortOrder = max + 1
	}

	t, err := s.tasks.Create(ctx, repositories.CreateTaskParams{
		UserID:      userID,
		Title:       req.Title,
		Description: req.Description,
		Address:     req.Address,
		Priority:    req.Priority,
		TaskType:    req.TaskType,
		SortOrder:   sortOrder,
		StartAt:     req.StartAt,
		EndAt:       req.EndAt,
	})
	if err != nil {
		return nil, err
	}
	resp := toTaskResponse(t)
	return &resp, nil
}

func (s *taskService) GetTask(ctx context.Context, id, userID uuid.UUID) (*TaskResponse, error) {
	t, err := s.tasks.GetByID(ctx, id, userID)
	if errors.Is(err, repositories.ErrNotFound) {
		return nil, apierr.New(404, "TASK_NOT_FOUND", "task not found")
	}
	if err != nil {
		return nil, err
	}
	resp := toTaskResponse(t)
	return &resp, nil
}

func (s *taskService) UpdateTask(ctx context.Context, id, userID uuid.UUID, req UpdateTaskRequest) (*TaskResponse, error) {
	params := repositories.UpdateTaskParams{
		Title:       req.Title,
		Description: req.Description,
		Address:     req.Address,
		Priority:    req.Priority,
		TaskType:    req.TaskType,
		Status:      req.Status,
		StartAt:     req.StartAt,
		EndAt:       req.EndAt,
	}
	if req.SortOrder != nil {
		params.SortOrder = req.SortOrder
	}

	// Server-side: setting CANCELLED status auto-sets cancelled_at
	if req.Status != nil && *req.Status == repositories.TaskStatusCancelled {
		now := time.Now().UTC()
		params.CancelledAt = &now
	}

	t, err := s.tasks.Update(ctx, id, userID, params)
	if errors.Is(err, repositories.ErrNotFound) {
		return nil, apierr.New(404, "TASK_NOT_FOUND", "task not found")
	}
	if err != nil {
		return nil, err
	}
	resp := toTaskResponse(t)
	return &resp, nil
}

func (s *taskService) DeleteTask(ctx context.Context, id, userID uuid.UUID) error {
	err := s.tasks.Delete(ctx, id, userID)
	if errors.Is(err, repositories.ErrNotFound) {
		return apierr.New(404, "TASK_NOT_FOUND", "task not found")
	}
	return err
}

// CompleteTask marks a task COMPLETED and triggers the gamification engine.
// CANCELLED tasks must already be filtered out by the repository (UPDATE WHERE status='PENDING').
func (s *taskService) CompleteTask(ctx context.Context, id, userID uuid.UUID) (*CompleteTaskResponse, error) {
	task, err := s.tasks.Complete(ctx, id, userID)
	if errors.Is(err, repositories.ErrNotFound) || errors.Is(err, repositories.ErrConflict) {
		// ErrNotFound  = task doesn't belong to this user
		// ErrConflict  = task already completed or cancelled (status != PENDING)
		return nil, apierr.New(409, "TASK_ALREADY_RESOLVED", "task is already completed or cancelled")
	}
	if err != nil {
		return nil, err
	}

	// Trigger gamification — non-fatal on error (log + return empty delta)
	delta, err := s.gamify.OnTaskCompleted(ctx, userID)
	if err != nil {
		slog.ErrorContext(ctx, "gamification update failed", "user_id", userID, "err", err) // GOV-010 §2.2
		delta = &GamificationDelta{}
	}

	taskResp := toTaskResponse(task)
	return &CompleteTaskResponse{Task: taskResp, GamificationDelta: *delta}, nil
}

func (s *taskService) UpdateSortOrder(ctx context.Context, id, userID uuid.UUID, sortOrder int) error {
	if sortOrder < 0 {
		return apierr.New(422, "VALIDATION_ERROR", "sort_order must be a non-negative integer")
	}
	err := s.tasks.UpdateSortOrder(ctx, id, userID, sortOrder)
	if errors.Is(err, repositories.ErrNotFound) {
		return apierr.New(404, "TASK_NOT_FOUND", "task not found")
	}
	return err
}

// ────────────────────────────────────────────────────────────────────────────
// Mapping helper
// ────────────────────────────────────────────────────────────────────────────

func toTaskResponse(t *repositories.Task) TaskResponse {
	return TaskResponse{
		ID:              t.ID,
		UserID:          t.UserID,
		RecurringRuleID: t.RecurringRuleID,
		Title:           t.Title,
		Description:     t.Description,
		Address:         t.Address,
		Priority:        string(t.Priority),
		TaskType:        string(t.TaskType),
		Status:          string(t.Status),
		IsOverdue:       t.IsOverdue,
		SortOrder:       t.SortOrder,
		IsDetached:      t.IsDetached,
		StartAt:         t.StartAt,
		EndAt:           t.EndAt,
		CompletedAt:     t.CompletedAt,
		CancelledAt:     t.CancelledAt,
		CreatedAt:       t.CreatedAt,
		UpdatedAt:       t.UpdatedAt,
	}
}
