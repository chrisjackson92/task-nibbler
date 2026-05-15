package repositories

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ────────────────────────────────────────────────────────────────────────────
// Model
// ────────────────────────────────────────────────────────────────────────────

// RecurringRule is a row from the recurring_rules table.
type RecurringRule struct {
	ID        uuid.UUID
	UserID    uuid.UUID
	RRule     string // iCal RRULE string e.g. "FREQ=DAILY;INTERVAL=1"
	IsActive  bool
	CreatedAt time.Time
	UpdatedAt time.Time
}

// ────────────────────────────────────────────────────────────────────────────
// Interface
// ────────────────────────────────────────────────────────────────────────────

// RecurringRuleRepository manages data access for recurring_rules.
type RecurringRuleRepository interface {
	// Create inserts a new active recurring rule.
	Create(ctx context.Context, userID uuid.UUID, rrule string) (*RecurringRule, error)

	// GetByID returns the rule for the given id (no user scope — used internally).
	GetByID(ctx context.Context, id uuid.UUID) (*RecurringRule, error)

	// ListActive returns all is_active=TRUE rules (used by nightly expansion cron).
	ListActive(ctx context.Context) ([]*RecurringRule, error)

	// Update sets the rrule string on a rule (used by scope=this_and_future).
	Update(ctx context.Context, id uuid.UUID, rrule string) error

	// Deactivate sets is_active=FALSE (soft-delete; scope=this_and_future delete flow).
	Deactivate(ctx context.Context, id uuid.UUID) error
}

// ────────────────────────────────────────────────────────────────────────────
// Implementation
// ────────────────────────────────────────────────────────────────────────────

type recurringRuleRepository struct {
	pool *pgxpool.Pool
}

// NewRecurringRuleRepository creates a RecurringRuleRepository.
func NewRecurringRuleRepository(pool *pgxpool.Pool) RecurringRuleRepository {
	return &recurringRuleRepository{pool: pool}
}

func (r *recurringRuleRepository) Create(ctx context.Context, userID uuid.UUID, rrule string) (*RecurringRule, error) {
	row := r.pool.QueryRow(ctx, `
		INSERT INTO recurring_rules (user_id, rrule)
		VALUES ($1, $2)
		RETURNING id, user_id, rrule, is_active, created_at, updated_at`,
		userID, rrule,
	)
	return scanRule(row)
}

func (r *recurringRuleRepository) GetByID(ctx context.Context, id uuid.UUID) (*RecurringRule, error) {
	row := r.pool.QueryRow(ctx, `
		SELECT id, user_id, rrule, is_active, created_at, updated_at
		FROM recurring_rules WHERE id = $1`,
		id,
	)
	rule, err := scanRule(row)
	if err != nil {
		return nil, err
	}
	if rule == nil {
		return nil, ErrNotFound
	}
	return rule, nil
}

func (r *recurringRuleRepository) ListActive(ctx context.Context) ([]*RecurringRule, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT id, user_id, rrule, is_active, created_at, updated_at
		FROM recurring_rules
		WHERE is_active = TRUE`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var rules []*RecurringRule
	for rows.Next() {
		var rule RecurringRule
		if err := rows.Scan(&rule.ID, &rule.UserID, &rule.RRule, &rule.IsActive, &rule.CreatedAt, &rule.UpdatedAt); err != nil {
			return nil, err
		}
		rules = append(rules, &rule)
	}
	return rules, rows.Err()
}

func (r *recurringRuleRepository) Update(ctx context.Context, id uuid.UUID, rrule string) error {
	tag, err := r.pool.Exec(ctx, `
		UPDATE recurring_rules SET rrule = $1, updated_at = NOW()
		WHERE id = $2`,
		rrule, id,
	)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func (r *recurringRuleRepository) Deactivate(ctx context.Context, id uuid.UUID) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE recurring_rules SET is_active = FALSE, updated_at = NOW()
		WHERE id = $1`,
		id,
	)
	return err
}

// scanRule reads a RecurringRule from a single row. Returns nil (not error) when no rows.
func scanRule(row interface {
	Scan(dest ...any) error
}) (*RecurringRule, error) {
	var rule RecurringRule
	err := row.Scan(&rule.ID, &rule.UserID, &rule.RRule, &rule.IsActive, &rule.CreatedAt, &rule.UpdatedAt)
	if err != nil {
		return nil, err
	}
	return &rule, nil
}
