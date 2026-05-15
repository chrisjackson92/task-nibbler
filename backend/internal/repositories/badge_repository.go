package repositories

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ────────────────────────────────────────────────────────────────────────────
// Badge model
// ────────────────────────────────────────────────────────────────────────────

// BadgeCatalogEntry is a row from the badges table (catalog, read-only at runtime).
type BadgeCatalogEntry struct {
	ID          string
	Name        string
	Description string
	Emoji       string
	TriggerType string
}

// UserBadge is a row from user_badges (an earned badge).
type UserBadge struct {
	ID       uuid.UUID
	UserID   uuid.UUID
	BadgeID  string
	EarnedAt time.Time
}

// ────────────────────────────────────────────────────────────────────────────
// Interface
// ────────────────────────────────────────────────────────────────────────────

// BadgeRepository handles data access for badge award logic.
// Defined in repositories/ to avoid import cycles.
type BadgeRepository interface {
	// TryAward inserts a user_badge row using ON CONFLICT DO NOTHING.
	// Returns true if the badge was newly awarded, false if already owned.
	TryAward(ctx context.Context, userID uuid.UUID, badgeID string) (bool, error)

	// GetUserBadges returns all earned badges for a user, ordered by earned_at DESC.
	GetUserBadges(ctx context.Context, userID uuid.UUID) ([]*UserBadge, error)

	// GetAllBadges returns all 14 catalog entries ordered by created_at ASC (insertion order).
	GetAllBadges(ctx context.Context) ([]*BadgeCatalogEntry, error)

	// CountTasksCompletedToday returns how many tasks the user completed on UTC today.
	// Used by the OVERACHIEVER badge check (≥10 completions in one day).
	CountTasksCompletedToday(ctx context.Context, userID uuid.UUID) (int, error)
}

// ────────────────────────────────────────────────────────────────────────────
// Implementation
// ────────────────────────────────────────────────────────────────────────────

type badgeRepository struct {
	pool *pgxpool.Pool
}

// NewBadgeRepository creates a BadgeRepository backed by a pgx pool.
func NewBadgeRepository(pool *pgxpool.Pool) BadgeRepository {
	return &badgeRepository{pool: pool}
}

func (r *badgeRepository) TryAward(ctx context.Context, userID uuid.UUID, badgeID string) (bool, error) {
	tag, err := r.pool.Exec(ctx, `
		INSERT INTO user_badges (user_id, badge_id)
		VALUES ($1, $2)
		ON CONFLICT (user_id, badge_id) DO NOTHING`,
		userID, badgeID,
	)
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() == 1, nil
}

func (r *badgeRepository) GetUserBadges(ctx context.Context, userID uuid.UUID) ([]*UserBadge, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT id, user_id, badge_id, earned_at
		FROM user_badges
		WHERE user_id = $1
		ORDER BY earned_at DESC`,
		userID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var badges []*UserBadge
	for rows.Next() {
		var ub UserBadge
		if err := rows.Scan(&ub.ID, &ub.UserID, &ub.BadgeID, &ub.EarnedAt); err != nil {
			return nil, err
		}
		badges = append(badges, &ub)
	}
	return badges, rows.Err()
}

func (r *badgeRepository) GetAllBadges(ctx context.Context) ([]*BadgeCatalogEntry, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT id, name, description, emoji, trigger_type
		FROM badges
		ORDER BY created_at ASC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var catalog []*BadgeCatalogEntry
	for rows.Next() {
		var b BadgeCatalogEntry
		if err := rows.Scan(&b.ID, &b.Name, &b.Description, &b.Emoji, &b.TriggerType); err != nil {
			return nil, err
		}
		catalog = append(catalog, &b)
	}
	return catalog, rows.Err()
}

func (r *badgeRepository) CountTasksCompletedToday(ctx context.Context, userID uuid.UUID) (int, error) {
	today := "current_date" // server-side UTC date
	var count int
	err := r.pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM tasks
		WHERE user_id = $1
		  AND status = 'COMPLETED'
		  AND completed_at::date = `+today,
		userID,
	).Scan(&count)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, nil
	}
	return count, err
}
