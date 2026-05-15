package repositories

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ────────────────────────────────────────────────────────────────────────────
// Types
// ────────────────────────────────────────────────────────────────────────────

// AttachmentStatus mirrors the DB attachment_status enum.
type AttachmentStatus string

const (
	AttachmentStatusPending  AttachmentStatus = "PENDING"
	AttachmentStatusComplete AttachmentStatus = "COMPLETE"
)

// Attachment represents a task_attachments row.
type Attachment struct {
	ID               uuid.UUID
	TaskID           uuid.UUID
	UserID           uuid.UUID
	Status           AttachmentStatus
	S3Key            string
	MimeType         string
	SizeBytes        *int64
	OriginalFilename string
	CreatedAt        time.Time
	ConfirmedAt      *time.Time
}

// AttachmentCleanupRow holds the S3 key of a PENDING attachment to be cleaned up.
type AttachmentCleanupRow struct {
	ID    uuid.UUID
	S3Key string
}

// ────────────────────────────────────────────────────────────────────────────
// Interface (consumer-side — satisfies GOV-010 §6.1)
// ────────────────────────────────────────────────────────────────────────────

// AttachmentRepository is the data access interface for task_attachments.
// Defined in repositories/ (producer) to avoid import cycles.
type AttachmentRepository interface {
	Create(ctx context.Context, taskID, userID uuid.UUID, s3Key, mimeType, filename string, sizeBytes *int64) (*Attachment, error)
	GetByID(ctx context.Context, id, userID uuid.UUID) (*Attachment, error)
	ListByTaskID(ctx context.Context, taskID, userID uuid.UUID) ([]*Attachment, error)
	CountComplete(ctx context.Context, taskID uuid.UUID) (int, error)
	MarkComplete(ctx context.Context, id, userID uuid.UUID) (*Attachment, error)
	Delete(ctx context.Context, id, userID uuid.UUID) (s3Key string, err error)
	DeletePendingOlderThan(ctx context.Context, olderThan time.Time) ([]*AttachmentCleanupRow, error)
}

// ────────────────────────────────────────────────────────────────────────────
// Implementation
// ────────────────────────────────────────────────────────────────────────────

type attachmentRepository struct {
	pool *pgxpool.Pool
}

// NewAttachmentRepository creates an AttachmentRepository backed by a pgx pool.
func NewAttachmentRepository(pool *pgxpool.Pool) AttachmentRepository {
	return &attachmentRepository{pool: pool}
}

func (r *attachmentRepository) Create(ctx context.Context, taskID, userID uuid.UUID, s3Key, mimeType, filename string, sizeBytes *int64) (*Attachment, error) {
	row := r.pool.QueryRow(ctx, `
		INSERT INTO task_attachments (task_id, user_id, s3_key, mime_type, original_filename, size_bytes)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id, task_id, user_id, status, s3_key, mime_type, size_bytes, original_filename, created_at, confirmed_at`,
		taskID, userID, s3Key, mimeType, filename, sizeBytes,
	)
	return scanAttachment(row)
}

func (r *attachmentRepository) GetByID(ctx context.Context, id, userID uuid.UUID) (*Attachment, error) {
	row := r.pool.QueryRow(ctx, `
		SELECT id, task_id, user_id, status, s3_key, mime_type, size_bytes, original_filename, created_at, confirmed_at
		FROM task_attachments
		WHERE id = $1 AND user_id = $2`,
		id, userID,
	)
	a, err := scanAttachment(row)
	if err != nil {
		return nil, fmt.Errorf("attachment_repository.GetByID: %w", err)
	}
	return a, nil
}

func (r *attachmentRepository) ListByTaskID(ctx context.Context, taskID, userID uuid.UUID) ([]*Attachment, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT id, task_id, user_id, status, s3_key, mime_type, size_bytes, original_filename, created_at, confirmed_at
		FROM task_attachments
		WHERE task_id = $1 AND user_id = $2 AND status = 'COMPLETE'
		ORDER BY confirmed_at ASC`,
		taskID, userID,
	)
	if err != nil {
		return nil, fmt.Errorf("attachment_repository.ListByTaskID: %w", err)
	}
	defer rows.Close()

	var attachments []*Attachment
	for rows.Next() {
		a, err := scanAttachmentFromRows(rows)
		if err != nil {
			return nil, err
		}
		attachments = append(attachments, a)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return attachments, nil
}

func (r *attachmentRepository) CountComplete(ctx context.Context, taskID uuid.UUID) (int, error) {
	var count int
	err := r.pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM task_attachments WHERE task_id = $1 AND status = 'COMPLETE'`, taskID,
	).Scan(&count)
	if err != nil {
		return 0, fmt.Errorf("attachment_repository.CountComplete: %w", err)
	}
	return count, nil
}

func (r *attachmentRepository) MarkComplete(ctx context.Context, id, userID uuid.UUID) (*Attachment, error) {
	row := r.pool.QueryRow(ctx, `
		UPDATE task_attachments
		SET status = 'COMPLETE', confirmed_at = NOW()
		WHERE id = $1 AND user_id = $2 AND status = 'PENDING'
		RETURNING id, task_id, user_id, status, s3_key, mime_type, size_bytes, original_filename, created_at, confirmed_at`,
		id, userID,
	)
	a, err := scanAttachment(row)
	if err != nil {
		return nil, fmt.Errorf("attachment_repository.MarkComplete: %w", err)
	}
	return a, nil
}

func (r *attachmentRepository) Delete(ctx context.Context, id, userID uuid.UUID) (string, error) {
	var s3Key string
	err := r.pool.QueryRow(ctx, `
		DELETE FROM task_attachments WHERE id = $1 AND user_id = $2 RETURNING s3_key`,
		id, userID,
	).Scan(&s3Key)
	if err != nil {
		return "", fmt.Errorf("attachment_repository.Delete: %w", mapAttachmentError(err))
	}
	return s3Key, nil
}

func (r *attachmentRepository) DeletePendingOlderThan(ctx context.Context, olderThan time.Time) ([]*AttachmentCleanupRow, error) {
	rows, err := r.pool.Query(ctx, `
		DELETE FROM task_attachments
		WHERE status = 'PENDING' AND created_at < $1
		RETURNING id, s3_key`,
		olderThan,
	)
	if err != nil {
		return nil, fmt.Errorf("attachment_repository.DeletePendingOlderThan: %w", err)
	}
	defer rows.Close()

	var result []*AttachmentCleanupRow
	for rows.Next() {
		var row AttachmentCleanupRow
		if err := rows.Scan(&row.ID, &row.S3Key); err != nil {
			return nil, err
		}
		result = append(result, &row)
	}
	return result, rows.Err()
}

// ────────────────────────────────────────────────────────────────────────────
// Helpers
// ────────────────────────────────────────────────────────────────────────────

type scannable interface {
	Scan(dest ...any) error
}

func scanAttachment(row scannable) (*Attachment, error) {
	var a Attachment
	err := row.Scan(
		&a.ID, &a.TaskID, &a.UserID,
		&a.Status, &a.S3Key, &a.MimeType,
		&a.SizeBytes, &a.OriginalFilename,
		&a.CreatedAt, &a.ConfirmedAt,
	)
	if err != nil {
		return nil, mapAttachmentError(err)
	}
	return &a, nil
}

func scanAttachmentFromRows(rows interface{ Scan(dest ...any) error }) (*Attachment, error) {
	return scanAttachment(rows)
}

func mapAttachmentError(err error) error {
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrNotFound
	}
	return err
}
