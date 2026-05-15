package services

import (
	"context"
	"fmt"
	"path/filepath"
	"strings"
	"time"

	"github.com/chrisjackson92/task-nibbler/backend/internal/apierr"
	"github.com/chrisjackson92/task-nibbler/backend/internal/repositories"
	s3client "github.com/chrisjackson92/task-nibbler/backend/internal/s3client"
	"github.com/google/uuid"
)

// ────────────────────────────────────────────────────────────────────────────
// Constants per CON-002 §4
// ────────────────────────────────────────────────────────────────────────────

const (
	maxAttachmentsPerTask = 10
	maxFileSizeBytes      = 200 * 1024 * 1024 // 200 MiB
	putURLTTL             = 15 * time.Minute
	getURLTTL             = 60 * time.Minute
)

// allowedMIMETypes is the application-layer allowlist for uploaded file types.
var allowedMIMETypes = map[string]bool{
	"image/jpeg":                                                   true,
	"image/png":                                                    true,
	"image/gif":                                                    true,
	"image/webp":                                                   true,
	"image/heic":                                                   true,
	"image/heif":                                                   true,
	"application/pdf":                                              true,
	"text/plain":                                                   true,
	"application/msword":                                           true,
	"application/vnd.openxmlformats-officedocument.wordprocessingml.document": true,
	"application/vnd.ms-excel":                                    true,
	"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet":       true,
	"video/mp4":                                                    true,
	"video/quicktime":                                              true,
}

// ────────────────────────────────────────────────────────────────────────────
// Request / Response DTOs
// ────────────────────────────────────────────────────────────────────────────

// PreRegisterRequest is the body for POST /tasks/:id/attachments.
type PreRegisterRequest struct {
	Filename  string `json:"filename" binding:"required"`
	MimeType  string `json:"mime_type" binding:"required"`
	SizeBytes int64  `json:"size_bytes" binding:"required,min=1"`
}

// PreRegisterResponse is the 201 body for POST /tasks/:id/attachments.
type PreRegisterResponse struct {
	AttachmentID string    `json:"attachment_id"`
	UploadURL    string    `json:"upload_url"`
	ExpiresAt    time.Time `json:"expires_at"`
}

// AttachmentResponse is the item shape for GET /tasks/:id/attachments.
type AttachmentResponse struct {
	ID               uuid.UUID  `json:"id"`
	TaskID           uuid.UUID  `json:"task_id"`
	Filename         string     `json:"filename"`
	MimeType         string     `json:"mime_type"`
	SizeBytes        *int64     `json:"size_bytes"`
	CreatedAt        time.Time  `json:"created_at"`
	ConfirmedAt      *time.Time `json:"confirmed_at"`
}

// DownloadURLResponse is the body for GET /tasks/:id/attachments/:aid/url.
type DownloadURLResponse struct {
	URL       string    `json:"url"`
	ExpiresAt time.Time `json:"expires_at"`
}

// ────────────────────────────────────────────────────────────────────────────
// Interface
// ────────────────────────────────────────────────────────────────────────────

// AttachmentService handles pre-registration, confirmation, listing, download URLs, and deletion.
type AttachmentService interface {
	PreRegister(ctx context.Context, taskID, userID uuid.UUID, req PreRegisterRequest) (*PreRegisterResponse, error)
	Confirm(ctx context.Context, attachmentID, userID uuid.UUID) error
	List(ctx context.Context, taskID, userID uuid.UUID) ([]*AttachmentResponse, error)
	GetDownloadURL(ctx context.Context, attachmentID, userID uuid.UUID) (*DownloadURLResponse, error)
	Delete(ctx context.Context, attachmentID, userID uuid.UUID) error
}

// ────────────────────────────────────────────────────────────────────────────
// Implementation
// ────────────────────────────────────────────────────────────────────────────

type attachmentService struct {
	repo repositories.AttachmentRepository
	s3   s3client.Client
}

// NewAttachmentService creates an AttachmentService.
func NewAttachmentService(repo repositories.AttachmentRepository, s3 s3client.Client) AttachmentService {
	return &attachmentService{repo: repo, s3: s3}
}

// PreRegister validates constraints, creates a PENDING attachment row, and returns a presigned PUT URL.
// Pattern A flow: client PUTs directly to S3 using the URL, then calls Confirm.
func (s *attachmentService) PreRegister(ctx context.Context, taskID, userID uuid.UUID, req PreRegisterRequest) (*PreRegisterResponse, error) {
	// Validate MIME type
	if !allowedMIMETypes[strings.ToLower(req.MimeType)] {
		return nil, apierr.ErrInvalidMIMEType
	}

	// Validate file size (< 200 MiB)
	if req.SizeBytes > maxFileSizeBytes {
		return nil, apierr.ErrFileTooLarge
	}

	// Count existing COMPLETE attachments
	count, err := s.repo.CountComplete(ctx, taskID)
	if err != nil {
		return nil, fmt.Errorf("attachment_service.PreRegister count: %w", err)
	}
	if count >= maxAttachmentsPerTask {
		return nil, apierr.ErrAttachmentLimit
	}

	// Build S3 key: {user_id}/{task_id}/{attachment_id}.{ext}
	// The attachment_id is generated here so the key is deterministic before DB insert.
	attachmentID := uuid.New()
	ext := filepath.Ext(req.Filename) // e.g. ".jpg"
	s3Key := fmt.Sprintf("%s/%s/%s%s",
		userID.String(),
		taskID.String(),
		attachmentID.String(),
		ext,
	)

	// Generate presigned PUT URL first (if S3 fails, no DB row is left orphaned)
	uploadURL, expiresAt, err := s.s3.PresignPutURL(ctx, s3Key, req.MimeType, putURLTTL)
	if err != nil {
		return nil, fmt.Errorf("attachment_service.PreRegister presign: %w", err)
	}

	// Create PENDING row in DB — use the DB-assigned ID in the response, not the
	// locally-generated one (which was only used to build the deterministic S3 key).
	sz := req.SizeBytes
	attachment, err := s.repo.Create(ctx, taskID, userID, s3Key, req.MimeType, req.Filename, &sz)
	if err != nil {
		return nil, fmt.Errorf("attachment_service.PreRegister create: %w", err)
	}

	return &PreRegisterResponse{
		AttachmentID: attachment.ID.String(),
		UploadURL:    uploadURL,
		ExpiresAt:    expiresAt,
	}, nil
}

// Confirm marks a PENDING attachment as COMPLETE after the client has finished uploading to S3.
func (s *attachmentService) Confirm(ctx context.Context, attachmentID, userID uuid.UUID) error {
	_, err := s.repo.MarkComplete(ctx, attachmentID, userID)
	if err != nil {
		if err == repositories.ErrNotFound {
			// Either doesn't exist, doesn't belong to user, or is already COMPLETE
			return apierr.New(422, "ATTACHMENT_NOT_PENDING", "attachment not found or is not in PENDING state")
		}
		return fmt.Errorf("attachment_service.Confirm: %w", err)
	}
	return nil
}

// List returns all COMPLETE attachments for a task.
func (s *attachmentService) List(ctx context.Context, taskID, userID uuid.UUID) ([]*AttachmentResponse, error) {
	attachments, err := s.repo.ListByTaskID(ctx, taskID, userID)
	if err != nil {
		return nil, fmt.Errorf("attachment_service.List: %w", err)
	}
	result := make([]*AttachmentResponse, 0, len(attachments))
	for _, a := range attachments {
		result = append(result, toAttachmentResponse(a))
	}
	return result, nil
}

// GetDownloadURL returns a fresh presigned S3 GET URL (TTL 60 min per CON-002 §4).
func (s *attachmentService) GetDownloadURL(ctx context.Context, attachmentID, userID uuid.UUID) (*DownloadURLResponse, error) {
	a, err := s.repo.GetByID(ctx, attachmentID, userID)
	if err != nil {
		if err == repositories.ErrNotFound {
			return nil, apierr.ErrAttachmentNotFound
		}
		return nil, fmt.Errorf("attachment_service.GetDownloadURL: %w", err)
	}

	url, expiresAt, err := s.s3.PresignGetURL(ctx, a.S3Key, getURLTTL)
	if err != nil {
		return nil, fmt.Errorf("attachment_service.GetDownloadURL presign: %w", err)
	}
	return &DownloadURLResponse{URL: url, ExpiresAt: expiresAt}, nil
}

// Delete removes the S3 object first, then deletes the DB row.
// Per AUD-002-BE checklist: S3 must be deleted BEFORE DB row.
// If S3 fails, the DB row is preserved (no ghost objects).
func (s *attachmentService) Delete(ctx context.Context, attachmentID, userID uuid.UUID) error {
	// Fetch the S3 key first (also verifies ownership)
	a, err := s.repo.GetByID(ctx, attachmentID, userID)
	if err != nil {
		if err == repositories.ErrNotFound {
			return apierr.ErrAttachmentNotFound
		}
		return fmt.Errorf("attachment_service.Delete get: %w", err)
	}

	// Delete S3 object FIRST — if this fails, we abort (DB row preserved)
	if err := s.s3.DeleteObject(ctx, a.S3Key); err != nil {
		return fmt.Errorf("attachment_service.Delete s3: %w", err)
	}

	// Delete DB row
	if _, err := s.repo.Delete(ctx, attachmentID, userID); err != nil {
		// S3 already deleted — log the orphan risk but return error for observability
		return fmt.Errorf("attachment_service.Delete db: %w", err)
	}
	return nil
}

// ────────────────────────────────────────────────────────────────────────────
// Helpers
// ────────────────────────────────────────────────────────────────────────────

func toAttachmentResponse(a *repositories.Attachment) *AttachmentResponse {
	return &AttachmentResponse{
		ID:          a.ID,
		TaskID:      a.TaskID,
		Filename:    a.OriginalFilename,
		MimeType:    a.MimeType,
		SizeBytes:   a.SizeBytes,
		CreatedAt:   a.CreatedAt,
		ConfirmedAt: a.ConfirmedAt,
	}
}
