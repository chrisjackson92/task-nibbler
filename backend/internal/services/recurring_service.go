package services

import (
	"context"
	"fmt"
	"time"

	"github.com/chrisjackson92/task-nibbler/backend/internal/apierr"
	"github.com/chrisjackson92/task-nibbler/backend/internal/repositories"
	"github.com/google/uuid"
	rrulego "github.com/teambition/rrule-go"
)

// ────────────────────────────────────────────────────────────────────────────
// Request DTOs
// ────────────────────────────────────────────────────────────────────────────

// CreateRecurringRequest extends CreateTaskRequest with a required rrule field.
type CreateRecurringRequest struct {
	CreateTaskRequest
	RRule string `json:"rrule" binding:"required"`
}

// UpdateScopedRequest is used for PATCH /tasks/:id?scope=...
type UpdateScopedRequest struct {
	UpdateTaskRequest
	Scope string `form:"scope"` // "this_only" | "this_and_future"
	RRule string `json:"rrule"` // only relevant for this_and_future
}

// DeleteScopedRequest is used for DELETE /tasks/:id?scope=...
type DeleteScopedRequest struct {
	Scope string `form:"scope"` // "this_only" | "this_and_future"
}

// scope constants
const (
	ScopeThisOnly      = "this_only"
	ScopeThisAndFuture = "this_and_future"
)

// ────────────────────────────────────────────────────────────────────────────
// RecurringService interface
// ────────────────────────────────────────────────────────────────────────────

// RecurringService handles recurring task creation, scoped edits, and scoped deletes.
// One-time task operations remain in TaskService.
type RecurringService interface {
	// CreateRecurring creates a recurring_rule row and the first task instance.
	CreateRecurring(ctx context.Context, userID uuid.UUID, req CreateRecurringRequest) (*TaskResponse, error)

	// UpdateScoped applies a PATCH to a task respecting scope.
	//   scope=this_only     → sets is_detached=TRUE, updates only this instance
	//   scope=this_and_future → updates recurring_rule.rrule; deletes all PENDING after this task's start_at
	UpdateScoped(ctx context.Context, taskID, userID uuid.UUID, req UpdateScopedRequest) (*TaskResponse, error)

	// DeleteScoped deletes a task respecting scope.
	//   scope=this_only     → deletes only this concrete instance
	//   scope=this_and_future → sets rule is_active=FALSE; deletes PENDING instances after this task's start_at
	DeleteScoped(ctx context.Context, taskID, userID uuid.UUID, scope string) error
}

// ────────────────────────────────────────────────────────────────────────────
// Implementation
// ────────────────────────────────────────────────────────────────────────────

type recurringService struct {
	taskRepo repositories.TaskRepository
	ruleRepo repositories.RecurringRuleRepository
}

// NewRecurringService creates a RecurringService.
func NewRecurringService(
	taskRepo repositories.TaskRepository,
	ruleRepo repositories.RecurringRuleRepository,
) RecurringService {
	return &recurringService{taskRepo: taskRepo, ruleRepo: ruleRepo}
}

// CreateRecurring validates the RRULE, creates the recurring_rule row, then creates
// the first concrete task instance (with start_at derived from the first RRULE occurrence).
func (s *recurringService) CreateRecurring(ctx context.Context, userID uuid.UUID, req CreateRecurringRequest) (*TaskResponse, error) {
	// Validate RRULE syntax
	if _, err := rrulego.StrToRRule(req.RRule); err != nil {
		return nil, apierr.New(422, "INVALID_RRULE", fmt.Sprintf("invalid rrule: %s", err.Error()))
	}

	// Create the rule row first
	rule, err := s.ruleRepo.Create(ctx, userID, req.RRule)
	if err != nil {
		return nil, fmt.Errorf("recurring_service.CreateRecurring ruleCreate: %w", err)
	}

	// Resolve first occurrence for start_at
	rruleSet, _ := rrulego.StrToRRule(req.RRule)
	now := time.Now().UTC()
	firstOcc := rruleSet.After(now, true)

	var startAt *time.Time
	if !firstOcc.IsZero() {
		t := firstOcc.UTC()
		startAt = &t
	}

	// Create first concrete task instance
	ruleID := rule.ID
	params := repositories.CreateTaskParams{
		UserID:          userID,
		RecurringRuleID: &ruleID,
		Title:           req.Title,
		Description:     req.Description,
		Address:         req.Address,
		Priority:        repositories.Priority(req.Priority),
		TaskType:        repositories.TaskTypeRecurring,
		SortOrder:       0, // sort order assigned by expansion cron
		StartAt:         startAt,
		EndAt:           req.EndAt,
	}

	task, err := s.taskRepo.Create(ctx, params)
	if err != nil {
		return nil, fmt.Errorf("recurring_service.CreateRecurring taskCreate: %w", err)
	}

	resp := toTaskResponse(task)
	return &resp, nil
}

// UpdateScoped applies a PATCH respecting the scope parameter.
// Per SPR-005-BE spec: scope absent on RECURRING task → 422.
func (s *recurringService) UpdateScoped(ctx context.Context, taskID, userID uuid.UUID, req UpdateScopedRequest) (*TaskResponse, error) {
	// Validate scope
	if req.Scope != ScopeThisOnly && req.Scope != ScopeThisAndFuture {
		return nil, apierr.New(422, "VALIDATION_ERROR", "scope parameter required for recurring tasks: must be 'this_only' or 'this_and_future'")
	}

	// Fetch task (verifies ownership)
	task, err := s.taskRepo.GetByID(ctx, taskID, userID)
	if err != nil {
		return nil, mapTaskErr(err)
	}

	if req.Scope == ScopeThisOnly {
		// Detach this instance: mark is_detached=TRUE and apply the update to this task only.
		params := toUpdateParams(req.UpdateTaskRequest)
		params.SetIsDetached = true
		updated, err := s.taskRepo.Update(ctx, taskID, userID, params)
		if err != nil {
			return nil, mapTaskErr(err)
		}
		resp := toTaskResponse(updated)
		return &resp, nil
	}

	// scope=this_and_future
	if task.RecurringRuleID == nil {
		return nil, apierr.ErrTaskNotFound // safety: task has no rule (e.g. already detached)
	}

	// 1. Update recurring_rule.rrule (if new rrule provided)
	if req.RRule != "" {
		if _, err := rrulego.StrToRRule(req.RRule); err != nil {
			return nil, apierr.New(422, "INVALID_RRULE", fmt.Sprintf("invalid rrule: %s", err.Error()))
		}
		if err := s.ruleRepo.Update(ctx, *task.RecurringRuleID, req.RRule); err != nil {
			return nil, fmt.Errorf("recurring_service.UpdateScoped ruleUpdate: %w", err)
		}
	}

	// 2. Delete all PENDING instances from this task's start_at onwards
	fromDate := time.Now().UTC()
	if task.StartAt != nil {
		fromDate = *task.StartAt
	}
	if err := s.taskRepo.DeleteFuturePending(ctx, *task.RecurringRuleID, fromDate); err != nil {
		return nil, fmt.Errorf("recurring_service.UpdateScoped deleteFuture: %w", err)
	}

	// 3. Update this specific task instance
	updated, err := s.taskRepo.Update(ctx, taskID, userID, toUpdateParams(req.UpdateTaskRequest))
	if err != nil {
		return nil, mapTaskErr(err)
	}

	resp := toTaskResponse(updated)
	return &resp, nil
}

// DeleteScoped deletes a task respecting the scope parameter.
func (s *recurringService) DeleteScoped(ctx context.Context, taskID, userID uuid.UUID, scope string) error {
	if scope != ScopeThisOnly && scope != ScopeThisAndFuture {
		return apierr.New(422, "VALIDATION_ERROR", "scope parameter required for recurring tasks: must be 'this_only' or 'this_and_future'")
	}

	// Fetch task (verifies ownership)
	task, err := s.taskRepo.GetByID(ctx, taskID, userID)
	if err != nil {
		return mapTaskErr(err)
	}

	if scope == ScopeThisOnly {
		// Delete only this concrete instance
		return s.taskRepo.Delete(ctx, taskID, userID)
	}

	// scope=this_and_future
	if task.RecurringRuleID == nil {
		return s.taskRepo.Delete(ctx, taskID, userID) // no rule — just delete this task
	}

	fromDate := time.Now().UTC()
	if task.StartAt != nil {
		fromDate = *task.StartAt
	}

	// 1. Deactivate the rule (soft-delete — cron skips is_active=FALSE)
	if err := s.ruleRepo.Deactivate(ctx, *task.RecurringRuleID); err != nil {
		return fmt.Errorf("recurring_service.DeleteScoped deactivate: %w", err)
	}

	// 2. Delete all PENDING instances from this date onwards
	if err := s.taskRepo.DeleteFuturePending(ctx, *task.RecurringRuleID, fromDate); err != nil {
		return fmt.Errorf("recurring_service.DeleteScoped deleteFuture: %w", err)
	}

	return nil
}

// ────────────────────────────────────────────────────────────────────────────
// Helpers
// ────────────────────────────────────────────────────────────────────────────

// toUpdateParams converts a service-layer UpdateTaskRequest → repo-layer UpdateTaskParams.
func toUpdateParams(req UpdateTaskRequest) repositories.UpdateTaskParams {
	return repositories.UpdateTaskParams{
		Title:       req.Title,
		Description: req.Description,
		Address:     req.Address,
		Priority:    req.Priority,
		TaskType:    req.TaskType,
		Status:      req.Status,
		SortOrder:   req.SortOrder,
		StartAt:     req.StartAt,
		EndAt:       req.EndAt,
	}
}

// mapTaskErr maps repository-layer errors to API errors for recurring operations.
func mapTaskErr(err error) error {
	if err == repositories.ErrNotFound {
		return apierr.ErrTaskNotFound
	}
	return err
}
