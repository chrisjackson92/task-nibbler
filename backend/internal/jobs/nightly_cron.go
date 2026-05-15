package jobs

import (
	"context"
	"log/slog"
	"time"

	"github.com/chrisjackson92/task-nibbler/backend/internal/repositories"
	s3client "github.com/chrisjackson92/task-nibbler/backend/internal/s3client"
)

// AttachmentCleanupJob deletes PENDING attachment rows older than 1 hour
// and their corresponding S3 objects. Registered in the nightly cron scheduler.
type AttachmentCleanupJob struct {
	repo repositories.AttachmentRepository
	s3   s3client.Client
}

// NewAttachmentCleanupJob creates an AttachmentCleanupJob.
func NewAttachmentCleanupJob(repo repositories.AttachmentRepository, s3 s3client.Client) *AttachmentCleanupJob {
	return &AttachmentCleanupJob{repo: repo, s3: s3}
}

// Run executes the cleanup:
//  1. DELETE PENDING rows older than 1 hour from DB (RETURNING s3_key)
//  2. For each returned s3_key, delete the S3 object (best-effort, log on failure)
//
// Per GOV-010 §9.1: stateless — reads from DB, computes, writes to DB.
func (j *AttachmentCleanupJob) Run(ctx context.Context) {
	cutoff := time.Now().UTC().Add(-time.Hour)
	rows, err := j.repo.DeletePendingOlderThan(ctx, cutoff)
	if err != nil {
		slog.ErrorContext(ctx, "attachment cleanup: failed to delete pending rows", "err", err)
		return
	}

	slog.InfoContext(ctx, "attachment cleanup: deleted pending rows", "count", len(rows))

	deleted := 0
	for _, row := range rows {
		if ctx.Err() != nil {
			slog.WarnContext(ctx, "attachment cleanup: context cancelled, stopping S3 deletes", "remaining", len(rows)-deleted)
			return
		}
		if err := j.s3.DeleteObject(ctx, row.S3Key); err != nil {
			// Log and continue — the DB row is already gone; the S3 object is now an orphan.
			// An ops runbook should handle orphaned S3 objects via S3 lifecycle rules.
			slog.WarnContext(ctx, "attachment cleanup: failed to delete S3 object",
				"s3_key", row.S3Key, "attachment_id", row.ID, "err", err)
		}
		deleted++
	}

	slog.InfoContext(ctx, "attachment cleanup: S3 deletes complete",
		"deleted", deleted, "errors", len(rows)-deleted)
}
