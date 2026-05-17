// Package repositories provides data access layers that wrap pgx queries
// and return domain structs. This is the ONLY layer that handles pgx errors.
// Repositories never contain business logic.
package repositories

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// User is the domain struct for a user row.
type User struct {
	ID           uuid.UUID
	Email        string
	PasswordHash string
	DisplayName  *string // nullable
	Timezone     string
	CreatedAt    time.Time
	UpdatedAt    time.Time
}

// RefreshToken is the domain struct for a refresh_tokens row.
type RefreshToken struct {
	ID        uuid.UUID
	UserID    uuid.UUID
	TokenHash string
	ExpiresAt time.Time
	RevokedAt *time.Time
	CreatedAt time.Time
}

// PasswordResetToken is the domain struct for a password_reset_tokens row.
type PasswordResetToken struct {
	ID        uuid.UUID
	UserID    uuid.UUID
	TokenHash string
	ExpiresAt time.Time
	UsedAt    *time.Time
	CreatedAt time.Time
}

// GamificationState is the domain struct for a gamification_state row.
type GamificationState struct {
	ID                    uuid.UUID
	UserID                uuid.UUID
	StreakCount           int32
	LastActiveDate        *time.Time
	GraceUsedAt           *time.Time
	HasCompletedFirstTask bool
	TreeHealthScore       int32
	SpriteType            string // "sprite_a" | "sprite_b"
	TreeType              string // "tree_a" | "tree_b"
	CreatedAt             time.Time
	UpdatedAt             time.Time
}

// UserRepository handles all data access for the users table.
type UserRepository struct {
	pool *pgxpool.Pool
}

// NewUserRepository creates a new UserRepository.
func NewUserRepository(pool *pgxpool.Pool) *UserRepository {
	return &UserRepository{pool: pool}
}

// Create inserts a new user and returns the created row.
func (r *UserRepository) Create(ctx context.Context, email, passwordHash, timezone string) (*User, error) {
	row := r.pool.QueryRow(ctx,
		`INSERT INTO users (email, password_hash, timezone)
		 VALUES ($1, $2, $3)
		 RETURNING id, email, password_hash, display_name, timezone, created_at, updated_at`,
		strings.ToLower(email), passwordHash, timezone,
	)
	return scanUser(row)
}

// GetByEmail retrieves a user by email address (case-insensitive lookup).
func (r *UserRepository) GetByEmail(ctx context.Context, email string) (*User, error) {
	row := r.pool.QueryRow(ctx,
		`SELECT id, email, password_hash, display_name, timezone, created_at, updated_at
		 FROM users WHERE email = $1 LIMIT 1`,
		strings.ToLower(email),
	)
	return scanUser(row)
}

// GetByID retrieves a user by primary key.
func (r *UserRepository) GetByID(ctx context.Context, id uuid.UUID) (*User, error) {
	row := r.pool.QueryRow(ctx,
		`SELECT id, email, password_hash, display_name, timezone, created_at, updated_at
		 FROM users WHERE id = $1 LIMIT 1`,
		id,
	)
	return scanUser(row)
}

// Delete deletes a user by ID. FK cascades handle all child rows.
func (r *UserRepository) Delete(ctx context.Context, id uuid.UUID) error {
	_, err := r.pool.Exec(ctx, `DELETE FROM users WHERE id = $1`, id)
	return err
}

func (r *UserRepository) UpdatePassword(ctx context.Context, id uuid.UUID, newHash string) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE users SET password_hash = $2, updated_at = NOW() WHERE id = $1`,
		id, newHash,
	)
	return err
}

// UpdateProfile sets display_name and timezone for the user and returns the updated row.
func (r *UserRepository) UpdateProfile(ctx context.Context, id uuid.UUID, displayName *string, timezone string) (*User, error) {
	row := r.pool.QueryRow(ctx,
		`UPDATE users SET display_name = $2, timezone = $3, updated_at = NOW()
		 WHERE id = $1
		 RETURNING id, email, password_hash, display_name, timezone, created_at, updated_at`,
		id, displayName, timezone,
	)
	return scanUser(row)
}

// UpdateTimezone is kept for backwards-compat; use UpdateProfile for full edits.
func (r *UserRepository) UpdateTimezone(ctx context.Context, id uuid.UUID, timezone string) (*User, error) {
	return r.UpdateProfile(ctx, id, nil, timezone)
}

// ListAllUserIDs returns every user ID in the users table.
// Used by GamificationNightlyJob to fan-out decay/penalty over all users.
// Full-table scan is acceptable at MVP scale; add pagination if user count exceeds 10k.
func (r *UserRepository) ListAllUserIDs(ctx context.Context) ([]uuid.UUID, error) {
	rows, err := r.pool.Query(ctx, `SELECT id FROM users ORDER BY id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var ids []uuid.UUID
	for rows.Next() {
		var id uuid.UUID
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}

func scanUser(row pgx.Row) (*User, error) {
	u := &User{}
	err := row.Scan(&u.ID, &u.Email, &u.PasswordHash, &u.DisplayName, &u.Timezone, &u.CreatedAt, &u.UpdatedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, nil // caller checks nil
		}
		return nil, err
	}
	return u, nil
}

// UpdatePasswordHash sets a new bcrypt hash for the user's password.
func (r *UserRepository) UpdatePasswordHash(ctx context.Context, id uuid.UUID, hash string) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE users SET password_hash = $2, updated_at = NOW() WHERE id = $1`,
		id, hash,
	)
	return err
}

// RefreshTokenRepository handles data access for the refresh_tokens table.
type RefreshTokenRepository struct {
	pool *pgxpool.Pool
}

// NewRefreshTokenRepository creates a new RefreshTokenRepository.
func NewRefreshTokenRepository(pool *pgxpool.Pool) *RefreshTokenRepository {
	return &RefreshTokenRepository{pool: pool}
}

// HashToken returns the SHA-256 hex string of the raw token.
func HashToken(rawToken string) string {
	h := sha256.Sum256([]byte(rawToken))
	return hex.EncodeToString(h[:])
}

// Create stores a hashed refresh token in the database.
func (r *RefreshTokenRepository) Create(ctx context.Context, userID uuid.UUID, rawToken string, expiresAt time.Time) (*RefreshToken, error) {
	hash := HashToken(rawToken)
	row := r.pool.QueryRow(ctx,
		`INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
		 VALUES ($1, $2, $3)
		 RETURNING id, user_id, token_hash, expires_at, revoked_at, created_at`,
		userID, hash, expiresAt,
	)
	return scanRefreshToken(row)
}

// GetByRawToken retrieves a refresh token record by the raw token value.
func (r *RefreshTokenRepository) GetByRawToken(ctx context.Context, rawToken string) (*RefreshToken, error) {
	hash := HashToken(rawToken)
	row := r.pool.QueryRow(ctx,
		`SELECT id, user_id, token_hash, expires_at, revoked_at, created_at
		 FROM refresh_tokens WHERE token_hash = $1 LIMIT 1`,
		hash,
	)
	rt, err := scanRefreshToken(row)
	if err != nil {
		return nil, err
	}
	return rt, nil
}

// RevokeByRawToken marks a specific token as revoked.
func (r *RefreshTokenRepository) RevokeByRawToken(ctx context.Context, rawToken string) error {
	hash := HashToken(rawToken)
	_, err := r.pool.Exec(ctx,
		`UPDATE refresh_tokens SET revoked_at = NOW() WHERE token_hash = $1`,
		hash,
	)
	return err
}

// RevokeAllForUser revokes every active refresh token for a user (theft detection).
func (r *RefreshTokenRepository) RevokeAllForUser(ctx context.Context, userID uuid.UUID) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE refresh_tokens SET revoked_at = NOW()
		 WHERE user_id = $1 AND revoked_at IS NULL`,
		userID,
	)
	return err
}

func scanRefreshToken(row pgx.Row) (*RefreshToken, error) {
	rt := &RefreshToken{}
	err := row.Scan(&rt.ID, &rt.UserID, &rt.TokenHash, &rt.ExpiresAt, &rt.RevokedAt, &rt.CreatedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	return rt, nil
}

// PasswordResetRepository handles data access for the password_reset_tokens table.
type PasswordResetRepository struct {
	pool *pgxpool.Pool
}

// NewPasswordResetRepository creates a new PasswordResetRepository.
func NewPasswordResetRepository(pool *pgxpool.Pool) *PasswordResetRepository {
	return &PasswordResetRepository{pool: pool}
}

// InvalidatePrevious marks all unused, unexpired reset tokens for a user as used.
// Called before issuing a new reset token so only one is active at a time.
func (r *PasswordResetRepository) InvalidatePrevious(ctx context.Context, userID uuid.UUID) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE password_reset_tokens
		 SET used_at = NOW()
		 WHERE user_id = $1 AND used_at IS NULL AND expires_at > NOW()`,
		userID,
	)
	return err
}

// Create stores a new hashed password reset token.
func (r *PasswordResetRepository) Create(ctx context.Context, userID uuid.UUID, rawToken string, expiresAt time.Time) (*PasswordResetToken, error) {
	hash := HashToken(rawToken)
	row := r.pool.QueryRow(ctx,
		`INSERT INTO password_reset_tokens (user_id, token_hash, expires_at)
		 VALUES ($1, $2, $3)
		 RETURNING id, user_id, token_hash, expires_at, used_at, created_at`,
		userID, hash, expiresAt,
	)
	return scanPasswordResetToken(row)
}

// GetByRawToken retrieves a password reset token by its raw (unhashed) value.
func (r *PasswordResetRepository) GetByRawToken(ctx context.Context, rawToken string) (*PasswordResetToken, error) {
	hash := HashToken(rawToken)
	row := r.pool.QueryRow(ctx,
		`SELECT id, user_id, token_hash, expires_at, used_at, created_at
		 FROM password_reset_tokens WHERE token_hash = $1 LIMIT 1`,
		hash,
	)
	prt, err := scanPasswordResetToken(row)
	if err != nil {
		return nil, err
	}
	return prt, nil
}

// MarkUsed sets used_at on a password reset token to prevent reuse.
func (r *PasswordResetRepository) MarkUsed(ctx context.Context, rawToken string) error {
	hash := HashToken(rawToken)
	_, err := r.pool.Exec(ctx,
		`UPDATE password_reset_tokens SET used_at = NOW() WHERE token_hash = $1`,
		hash,
	)
	return err
}

func scanPasswordResetToken(row pgx.Row) (*PasswordResetToken, error) {
	prt := &PasswordResetToken{}
	err := row.Scan(&prt.ID, &prt.UserID, &prt.TokenHash, &prt.ExpiresAt, &prt.UsedAt, &prt.CreatedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	return prt, nil
}

// GamificationStateReader is the interface required by GamificationService.
// The concrete *GamificationRepository satisfies it automatically.
// Declared here (in the producer package) rather than in services/ to avoid
// import cycles — services imports repositories, not vice versa.
type GamificationStateReader interface {
	// Create seeds an initial gamification row for the user.
	// Used for lazy seeding if the registration seed failed non-fatally.
	Create(ctx context.Context, userID uuid.UUID) (*GamificationState, error)
	GetByUserID(ctx context.Context, userID uuid.UUID) (*GamificationState, error)
	UpdateOnComplete(ctx context.Context, userID uuid.UUID, newStreakCount int, lastActiveDate time.Time) (*GamificationState, error)
	// UpdateGraceUsedAt sets grace_used_at = graceDate (grace day consumed, streak preserved).
	UpdateGraceUsedAt(ctx context.Context, userID uuid.UUID, graceDate time.Time) error
	// UpdateNightlyDecay sets streak_count = newStreak and tree_health_score = newHealth (zero-completion decay).
	UpdateNightlyDecay(ctx context.Context, userID uuid.UUID, newStreak, newHealth int) error
	// UpdateTreeHealth sets tree_health_score = newHealth (overdue penalty in isolation).
	UpdateTreeHealth(ctx context.Context, userID uuid.UUID, newHealth int) error
	// UpdateCompanion persists the user's sprite and tree type selection.
	UpdateCompanion(ctx context.Context, userID uuid.UUID, spriteType, treeType string) (*GamificationState, error)
}

// GamificationRepository handles data access for the gamification_state table.
type GamificationRepository struct {
	pool *pgxpool.Pool
}

// NewGamificationRepository creates a new GamificationRepository.
func NewGamificationRepository(pool *pgxpool.Pool) *GamificationRepository {
	return &GamificationRepository{pool: pool}
}

// Create seeds the initial gamification state for a new user (tree_health=50, WELCOME state).
func (r *GamificationRepository) Create(ctx context.Context, userID uuid.UUID) (*GamificationState, error) {
	row := r.pool.QueryRow(ctx,
		`INSERT INTO gamification_state (user_id, streak_count, has_completed_first_task, tree_health_score)
		 VALUES ($1, 0, false, 50)
		 RETURNING id, user_id, streak_count, last_active_date, grace_used_at,
		           has_completed_first_task, tree_health_score, sprite_type, tree_type, created_at, updated_at`,
		userID,
	)
	return scanGamificationState(row)
}

// GetByUserID retrieves the gamification state for the given user.
func (r *GamificationRepository) GetByUserID(ctx context.Context, userID uuid.UUID) (*GamificationState, error) {
	row := r.pool.QueryRow(ctx,
		`SELECT id, user_id, streak_count, last_active_date, grace_used_at,
		        has_completed_first_task, tree_health_score, sprite_type, tree_type, created_at, updated_at
		 FROM gamification_state WHERE user_id = $1 LIMIT 1`,
		userID,
	)
	gs, err := scanGamificationState(row)
	if err != nil {
		return nil, err
	}
	if gs == nil {
		return nil, ErrNotFound
	}
	return gs, nil
}

// UpdateOnComplete atomically updates gamification state after a task is completed.
// newStreakCount and lastActiveDate are computed by the service layer.
// tree_health_score is incremented by 5 in the DB (capped at 100 via LEAST).
func (r *GamificationRepository) UpdateOnComplete(
	ctx context.Context,
	userID uuid.UUID,
	newStreakCount int,
	lastActiveDate time.Time,
) (*GamificationState, error) {
	row := r.pool.QueryRow(ctx,
		`UPDATE gamification_state SET
		   streak_count             = $1,
		   last_active_date         = $2,
		   has_completed_first_task = TRUE,
		   tree_health_score        = LEAST(tree_health_score + 5, 100),
		   updated_at               = NOW()
		 WHERE user_id = $3
		 RETURNING id, user_id, streak_count, last_active_date, grace_used_at,
		           has_completed_first_task, tree_health_score, sprite_type, tree_type, created_at, updated_at`,
		newStreakCount, lastActiveDate, userID,
	)
	gs, err := scanGamificationState(row)
	if err != nil {
		return nil, err
	}
	if gs == nil {
		return nil, ErrNotFound
	}
	return gs, nil
}

func scanGamificationState(row pgx.Row) (*GamificationState, error) {
	gs := &GamificationState{}
	err := row.Scan(
		&gs.ID, &gs.UserID, &gs.StreakCount, &gs.LastActiveDate, &gs.GraceUsedAt,
		&gs.HasCompletedFirstTask, &gs.TreeHealthScore, &gs.SpriteType, &gs.TreeType,
		&gs.CreatedAt, &gs.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	return gs, nil
}

// UpdateCompanion persists the user's sprite and tree type choice.
func (r *GamificationRepository) UpdateCompanion(ctx context.Context, userID uuid.UUID, spriteType, treeType string) (*GamificationState, error) {
	row := r.pool.QueryRow(ctx,
		`UPDATE gamification_state
		 SET sprite_type = $2, tree_type = $3, updated_at = NOW()
		 WHERE user_id = $1
		 RETURNING id, user_id, streak_count, last_active_date, grace_used_at,
		           has_completed_first_task, tree_health_score, sprite_type, tree_type, created_at, updated_at`,
		userID, spriteType, treeType,
	)
	gs, err := scanGamificationState(row)
	if err != nil {
		return nil, err
	}
	if gs == nil {
		return nil, ErrNotFound
	}
	return gs, nil
}

// UpdateGraceUsedAt sets grace_used_at to graceDate (grace consumed; streak preserved).
func (r *GamificationRepository) UpdateGraceUsedAt(ctx context.Context, userID uuid.UUID, graceDate time.Time) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE gamification_state
		SET grace_used_at = $1, updated_at = NOW()
		WHERE user_id = $2`,
		graceDate, userID,
	)
	return err
}

// UpdateNightlyDecay resets streak_count to newStreak and sets tree_health_score = newHealth.
// Called by the nightly zero-completion decay cron.
func (r *GamificationRepository) UpdateNightlyDecay(ctx context.Context, userID uuid.UUID, newStreak, newHealth int) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE gamification_state
		SET streak_count = $1, tree_health_score = GREATEST(0, LEAST(100, $2)), updated_at = NOW()
		WHERE user_id = $3`,
		newStreak, newHealth, userID,
	)
	return err
}

// UpdateTreeHealth sets tree_health_score to newHealth (clamped to [0, 100]).
// Called by the nightly overdue penalty cron.
func (r *GamificationRepository) UpdateTreeHealth(ctx context.Context, userID uuid.UUID, newHealth int) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE gamification_state
		SET tree_health_score = GREATEST(0, LEAST(100, $1)), updated_at = NOW()
		WHERE user_id = $2`,
		newHealth, userID,
	)
	return err
}
