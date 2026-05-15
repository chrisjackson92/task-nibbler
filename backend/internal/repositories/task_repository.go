package repositories

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ────────────────────────────────────────────────────────────────────────────
// Domain types
// ────────────────────────────────────────────────────────────────────────────

// Priority mirrors the task_priority Postgres enum.
type Priority string

const (
	PriorityLow      Priority = "LOW"
	PriorityMedium   Priority = "MEDIUM"
	PriorityHigh     Priority = "HIGH"
	PriorityCritical Priority = "CRITICAL"
)

// TaskType mirrors the task_type Postgres enum.
type TaskType string

const (
	TaskTypeOneTime   TaskType = "ONE_TIME"
	TaskTypeRecurring TaskType = "RECURRING"
)

// TaskStatus mirrors the task_status Postgres enum.
type TaskStatus string

const (
	TaskStatusPending   TaskStatus = "PENDING"
	TaskStatusCompleted TaskStatus = "COMPLETED"
	TaskStatusCancelled TaskStatus = "CANCELLED"
)

// Task is the repository-layer domain object.
// IsOverdue is computed at read time — it is never stored in the DB.
type Task struct {
	ID              uuid.UUID
	UserID          uuid.UUID
	RecurringRuleID *uuid.UUID
	Title           string
	Description     *string
	Address         *string
	Priority        Priority
	TaskType        TaskType
	Status          TaskStatus
	IsOverdue       bool // computed; not a DB column
	SortOrder       int
	IsDetached      bool
	StartAt         *time.Time
	EndAt           *time.Time
	CompletedAt     *time.Time
	CancelledAt     *time.Time
	CreatedAt       time.Time
	UpdatedAt       time.Time
}

// ListTasksFilter holds optional filter/sort/page parameters for ListTasks.
type ListTasksFilter struct {
	Status   *TaskStatus
	Priority *Priority
	Type     *TaskType
	From     *time.Time
	To       *time.Time
	Search   *string
	Sort     string // due_date | priority | sort_order | created_at
	Order    string // asc | desc
	Page     int
	PerPage  int
}

// TaskPage is the paginated result from ListTasks.
type TaskPage struct {
	Tasks      []*Task
	Total      int64
	Page       int
	PerPage    int
	TotalPages int
}

// CreateTaskParams holds validated input for task creation.
type CreateTaskParams struct {
	UserID          uuid.UUID
	RecurringRuleID *uuid.UUID
	Title           string
	Description     *string
	Address         *string
	Priority        Priority
	TaskType        TaskType
	SortOrder       int
	StartAt         *time.Time
	EndAt           *time.Time
}

// UpdateTaskParams holds optional fields for a partial task update.
type UpdateTaskParams struct {
	Title       *string
	Description *string
	Address     *string
	Priority    *Priority
	TaskType    *TaskType
	Status      *TaskStatus
	SortOrder   *int
	StartAt     *time.Time
	EndAt       *time.Time
	CancelledAt *time.Time
}

// ────────────────────────────────────────────────────────────────────────────
// Interface
// ────────────────────────────────────────────────────────────────────────────

// TaskRepository defines the data-access contract for tasks.
// All methods scope queries to the given userID to prevent cross-user access.
type TaskRepository interface {
	Create(ctx context.Context, params CreateTaskParams) (*Task, error)
	GetByID(ctx context.Context, id, userID uuid.UUID) (*Task, error)
	List(ctx context.Context, userID uuid.UUID, filter ListTasksFilter) (*TaskPage, error)
	Update(ctx context.Context, id, userID uuid.UUID, params UpdateTaskParams) (*Task, error)
	Delete(ctx context.Context, id, userID uuid.UUID) error
	Complete(ctx context.Context, id, userID uuid.UUID) (*Task, error)
	UpdateSortOrder(ctx context.Context, id, userID uuid.UUID, sortOrder int) error
	GetMaxSortOrder(ctx context.Context, userID uuid.UUID) (int, error)
}

// ────────────────────────────────────────────────────────────────────────────
// Implementation
// ────────────────────────────────────────────────────────────────────────────

type taskRepository struct {
	pool *pgxpool.Pool
}

// NewTaskRepository returns a TaskRepository backed by the provided pgx pool.
func NewTaskRepository(pool *pgxpool.Pool) TaskRepository {
	return &taskRepository{pool: pool}
}

// enrichTask computes the derived IsOverdue field. This field is NEVER stored
// in the database — doing so would violate the audit requirement in AUD-001-BE.
func enrichTask(t *Task) *Task {
	t.IsOverdue = t.Status == TaskStatusPending &&
		t.EndAt != nil &&
		t.EndAt.Before(time.Now().UTC())
	return t
}

func (r *taskRepository) Create(ctx context.Context, p CreateTaskParams) (*Task, error) {
	row := r.pool.QueryRow(ctx, `
		INSERT INTO tasks (
			user_id, recurring_rule_id, title, description, address,
			priority, task_type, sort_order, start_at, end_at
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
		RETURNING
			id, user_id, recurring_rule_id, title, description, address,
			priority, task_type, status, sort_order, is_detached,
			start_at, end_at, completed_at, cancelled_at, created_at, updated_at`,
		p.UserID, p.RecurringRuleID, p.Title, p.Description, p.Address,
		string(p.Priority), string(p.TaskType), p.SortOrder, p.StartAt, p.EndAt,
	)
	return scanTask(row)
}

func (r *taskRepository) GetByID(ctx context.Context, id, userID uuid.UUID) (*Task, error) {
	row := r.pool.QueryRow(ctx, `
		SELECT id, user_id, recurring_rule_id, title, description, address,
		       priority, task_type, status, sort_order, is_detached,
		       start_at, end_at, completed_at, cancelled_at, created_at, updated_at
		FROM tasks WHERE id = $1 AND user_id = $2`, id, userID)
	t, err := scanTask(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	return t, err
}

func (r *taskRepository) GetMaxSortOrder(ctx context.Context, userID uuid.UUID) (int, error) {
	var max pgtype.Int8
	err := r.pool.QueryRow(ctx,
		`SELECT COALESCE(MAX(sort_order), -1) FROM tasks WHERE user_id = $1`, userID,
	).Scan(&max)
	if err != nil {
		return 0, err
	}
	return int(max.Int64), nil
}

func (r *taskRepository) List(ctx context.Context, userID uuid.UUID, f ListTasksFilter) (*TaskPage, error) {
	if f.Page < 1 {
		f.Page = 1
	}
	if f.PerPage < 1 || f.PerPage > 100 {
		f.PerPage = 50
	}
	offset := (f.Page - 1) * f.PerPage

	sort := f.Sort
	if sort == "" {
		sort = "sort_order"
	}
	order := f.Order
	if order == "" {
		order = "asc"
	}

	// Count total for pagination metadata
	var total int64
	err := r.pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM tasks
		WHERE user_id = $1
		  AND ($2::task_status IS NULL OR status = $2)
		  AND ($3::task_priority IS NULL OR priority = $3)
		  AND ($4::task_type IS NULL OR task_type = $4)
		  AND ($5::timestamptz IS NULL OR end_at >= $5)
		  AND ($6::timestamptz IS NULL OR end_at <= $6)
		  AND ($7::text IS NULL OR
			    to_tsvector('english', title || ' ' || COALESCE(description,'')) @@
			    plainto_tsquery('english', $7))`,
		userID, statusArg(f.Status), priorityArg(f.Priority), typeArg(f.Type),
		f.From, f.To, f.Search,
	).Scan(&total)
	if err != nil {
		return nil, err
	}

	rows, err := r.pool.Query(ctx, `
		SELECT id, user_id, recurring_rule_id, title, description, address,
		       priority, task_type, status, sort_order, is_detached,
		       start_at, end_at, completed_at, cancelled_at, created_at, updated_at
		FROM tasks
		WHERE user_id = $1
		  AND ($2::task_status IS NULL OR status = $2)
		  AND ($3::task_priority IS NULL OR priority = $3)
		  AND ($4::task_type IS NULL OR task_type = $4)
		  AND ($5::timestamptz IS NULL OR end_at >= $5)
		  AND ($6::timestamptz IS NULL OR end_at <= $6)
		  AND ($7::text IS NULL OR
			    to_tsvector('english', title || ' ' || COALESCE(description,'')) @@
			    plainto_tsquery('english', $7))
		ORDER BY sort_order ASC
		LIMIT $8 OFFSET $9`,
		userID, statusArg(f.Status), priorityArg(f.Priority), typeArg(f.Type),
		f.From, f.To, f.Search, f.PerPage, offset,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var tasks []*Task
	for rows.Next() {
		t, err := scanTaskFromRows(rows)
		if err != nil {
			return nil, err
		}

		// Apply overdue filter in-memory (status=PENDING + end_at is past)
		if f.Status != nil && *f.Status == "overdue" {
			if !t.IsOverdue {
				continue
			}
		}
		tasks = append(tasks, t)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	totalPages := int((total + int64(f.PerPage) - 1) / int64(f.PerPage))
	return &TaskPage{
		Tasks:      tasks,
		Total:      total,
		Page:       f.Page,
		PerPage:    f.PerPage,
		TotalPages: totalPages,
	}, nil
}

func (r *taskRepository) Update(ctx context.Context, id, userID uuid.UUID, p UpdateTaskParams) (*Task, error) {
	row := r.pool.QueryRow(ctx, `
		UPDATE tasks SET
		  title        = COALESCE($3, title),
		  description  = COALESCE($4, description),
		  address      = COALESCE($5, address),
		  priority     = COALESCE($6::task_priority, priority),
		  task_type    = COALESCE($7::task_type, task_type),
		  status       = COALESCE($8::task_status, status),
		  sort_order   = COALESCE($9, sort_order),
		  start_at     = COALESCE($10, start_at),
		  end_at       = COALESCE($11, end_at),
		  cancelled_at = COALESCE($12, cancelled_at),
		  updated_at   = NOW()
		WHERE id = $1 AND user_id = $2
		RETURNING
		  id, user_id, recurring_rule_id, title, description, address,
		  priority, task_type, status, sort_order, is_detached,
		  start_at, end_at, completed_at, cancelled_at, created_at, updated_at`,
		id, userID,
		p.Title, p.Description, p.Address,
		priorityArg(p.Priority), typeArg(p.TaskType), statusArg(p.Status),
		p.SortOrder, p.StartAt, p.EndAt, p.CancelledAt,
	)
	t, err := scanTask(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	return t, err
}

func (r *taskRepository) Delete(ctx context.Context, id, userID uuid.UUID) error {
	tag, err := r.pool.Exec(ctx,
		`DELETE FROM tasks WHERE id = $1 AND user_id = $2`, id, userID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func (r *taskRepository) Complete(ctx context.Context, id, userID uuid.UUID) (*Task, error) {
	row := r.pool.QueryRow(ctx, `
		UPDATE tasks SET
		  status       = 'COMPLETED',
		  completed_at = NOW(),
		  updated_at   = NOW()
		WHERE id = $1 AND user_id = $2 AND status = 'PENDING'
		RETURNING
		  id, user_id, recurring_rule_id, title, description, address,
		  priority, task_type, status, sort_order, is_detached,
		  start_at, end_at, completed_at, cancelled_at, created_at, updated_at`,
		id, userID)
	t, err := scanTask(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrConflict // already completed or cancelled
	}
	return t, err
}

func (r *taskRepository) UpdateSortOrder(ctx context.Context, id, userID uuid.UUID, sortOrder int) error {
	tag, err := r.pool.Exec(ctx,
		`UPDATE tasks SET sort_order = $1, updated_at = NOW() WHERE id = $2 AND user_id = $3`,
		sortOrder, id, userID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// ────────────────────────────────────────────────────────────────────────────
// Scan helpers
// ────────────────────────────────────────────────────────────────────────────

type scanner interface {
	Scan(dest ...any) error
}

func scanTask(s scanner) (*Task, error) {
	var t Task
	var priority, taskType, status string
	var recurringRuleID pgtype.UUID
	err := s.Scan(
		&t.ID, &t.UserID, &recurringRuleID,
		&t.Title, &t.Description, &t.Address,
		&priority, &taskType, &status,
		&t.SortOrder, &t.IsDetached,
		&t.StartAt, &t.EndAt, &t.CompletedAt, &t.CancelledAt,
		&t.CreatedAt, &t.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	if recurringRuleID.Valid {
		id := uuid.UUID(recurringRuleID.Bytes)
		t.RecurringRuleID = &id
	}
	t.Priority = Priority(priority)
	t.TaskType = TaskType(taskType)
	t.Status = TaskStatus(status)
	return enrichTask(&t), nil
}

func scanTaskFromRows(rows pgx.Rows) (*Task, error) {
	var t Task
	var priority, taskType, status string
	var recurringRuleID pgtype.UUID
	err := rows.Scan(
		&t.ID, &t.UserID, &recurringRuleID,
		&t.Title, &t.Description, &t.Address,
		&priority, &taskType, &status,
		&t.SortOrder, &t.IsDetached,
		&t.StartAt, &t.EndAt, &t.CompletedAt, &t.CancelledAt,
		&t.CreatedAt, &t.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	if recurringRuleID.Valid {
		id := uuid.UUID(recurringRuleID.Bytes)
		t.RecurringRuleID = &id
	}
	t.Priority = Priority(priority)
	t.TaskType = TaskType(taskType)
	t.Status = TaskStatus(status)
	return enrichTask(&t), nil
}

// ────────────────────────────────────────────────────────────────────────────
// Null coercion helpers for optional filter args
// ────────────────────────────────────────────────────────────────────────────

func statusArg(s *TaskStatus) *string {
	if s == nil {
		return nil
	}
	v := string(*s)
	return &v
}

func priorityArg(p *Priority) *string {
	if p == nil {
		return nil
	}
	v := string(*p)
	return &v
}

func typeArg(t *TaskType) *string {
	if t == nil {
		return nil
	}
	v := string(*t)
	return &v
}
