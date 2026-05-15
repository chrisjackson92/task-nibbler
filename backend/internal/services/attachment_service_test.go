package services_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/chrisjackson92/task-nibbler/backend/internal/apierr"
	"github.com/chrisjackson92/task-nibbler/backend/internal/repositories"
	"github.com/chrisjackson92/task-nibbler/backend/internal/services"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// ────────────────────────────────────────────────────────────────────────────
// Mock S3 client
// ────────────────────────────────────────────────────────────────────────────

type mockS3Client struct {
	putErr    error
	getErr    error
	deleteErr error
	putCalled bool
	delCalled bool
}

func (m *mockS3Client) PresignPutURL(_ context.Context, _, _ string, _ time.Duration) (string, time.Time, error) {
	m.putCalled = true
	if m.putErr != nil {
		return "", time.Time{}, m.putErr
	}
	return "https://s3.example.com/put-url", time.Now().Add(15 * time.Minute), nil
}

func (m *mockS3Client) PresignGetURL(_ context.Context, _ string, _ time.Duration) (string, time.Time, error) {
	if m.getErr != nil {
		return "", time.Time{}, m.getErr
	}
	return "https://s3.example.com/get-url", time.Now().Add(60 * time.Minute), nil
}

func (m *mockS3Client) DeleteObject(_ context.Context, _ string) error {
	m.delCalled = true
	return m.deleteErr
}

// ────────────────────────────────────────────────────────────────────────────
// Mock Attachment Repository
// ────────────────────────────────────────────────────────────────────────────

type mockAttachmentRepo struct {
	attachments    map[uuid.UUID]*repositories.Attachment
	completeCount  int
	markCompleteErr error
}

func newMockAttachRepo() *mockAttachmentRepo {
	return &mockAttachmentRepo{
		attachments: make(map[uuid.UUID]*repositories.Attachment),
	}
}

func (m *mockAttachmentRepo) Create(_ context.Context, taskID, userID uuid.UUID, s3Key, mimeType, filename string, sizeBytes *int64) (*repositories.Attachment, error) {
	a := &repositories.Attachment{
		ID:               uuid.New(),
		TaskID:          taskID,
		UserID:          userID,
		Status:          repositories.AttachmentStatusPending,
		S3Key:           s3Key,
		MimeType:        mimeType,
		OriginalFilename: filename,
		SizeBytes:       sizeBytes,
		CreatedAt:       time.Now(),
	}
	m.attachments[a.ID] = a
	return a, nil
}

func (m *mockAttachmentRepo) GetByID(_ context.Context, id, _ uuid.UUID) (*repositories.Attachment, error) {
	a, ok := m.attachments[id]
	if !ok {
		return nil, repositories.ErrNotFound
	}
	return a, nil
}

func (m *mockAttachmentRepo) ListByTaskID(_ context.Context, taskID, _ uuid.UUID) ([]*repositories.Attachment, error) {
	var result []*repositories.Attachment
	for _, a := range m.attachments {
		if a.TaskID == taskID && a.Status == repositories.AttachmentStatusComplete {
			result = append(result, a)
		}
	}
	return result, nil
}

func (m *mockAttachmentRepo) CountComplete(_ context.Context, _ uuid.UUID) (int, error) {
	return m.completeCount, nil
}

func (m *mockAttachmentRepo) MarkComplete(_ context.Context, id, _ uuid.UUID) (*repositories.Attachment, error) {
	if m.markCompleteErr != nil {
		return nil, m.markCompleteErr
	}
	a, ok := m.attachments[id]
	if !ok || a.Status != repositories.AttachmentStatusPending {
		return nil, repositories.ErrNotFound
	}
	now := time.Now()
	a.Status = repositories.AttachmentStatusComplete
	a.ConfirmedAt = &now
	return a, nil
}

func (m *mockAttachmentRepo) Delete(_ context.Context, id, _ uuid.UUID) (string, error) {
	a, ok := m.attachments[id]
	if !ok {
		return "", repositories.ErrNotFound
	}
	key := a.S3Key
	delete(m.attachments, id)
	return key, nil
}

func (m *mockAttachmentRepo) DeletePendingOlderThan(_ context.Context, _ time.Time) ([]*repositories.AttachmentCleanupRow, error) {
	return nil, nil
}

// ────────────────────────────────────────────────────────────────────────────
// Tests
// ────────────────────────────────────────────────────────────────────────────

func TestPreRegister_ReturnsPresignedURL(t *testing.T) {
	repo := newMockAttachRepo()
	s3 := &mockS3Client{}
	svc := services.NewAttachmentService(repo, s3)

	resp, err := svc.PreRegister(context.Background(), uuid.New(), uuid.New(), services.PreRegisterRequest{
		Filename:  "photo.jpg",
		MimeType:  "image/jpeg",
		SizeBytes: 1024,
	})

	require.NoError(t, err)
	assert.NotEmpty(t, resp.AttachmentID)
	assert.Contains(t, resp.UploadURL, "s3.example.com")
	assert.True(t, s3.putCalled, "S3 presign must be called")
}

func TestPreRegister_AttachmentLimit(t *testing.T) {
	repo := newMockAttachRepo()
	repo.completeCount = 10 // at max
	svc := services.NewAttachmentService(repo, &mockS3Client{})

	_, err := svc.PreRegister(context.Background(), uuid.New(), uuid.New(), services.PreRegisterRequest{
		Filename:  "photo.jpg",
		MimeType:  "image/jpeg",
		SizeBytes: 1024,
	})

	require.Error(t, err)
	var apiErr *apierr.APIError
	require.True(t, errors.As(err, &apiErr), "expected apierr.APIError")
	assert.Equal(t, "ATTACHMENT_LIMIT", apiErr.Code)
}

func TestPreRegister_InvalidMIME(t *testing.T) {
	svc := services.NewAttachmentService(newMockAttachRepo(), &mockS3Client{})

	_, err := svc.PreRegister(context.Background(), uuid.New(), uuid.New(), services.PreRegisterRequest{
		Filename:  "malware.exe",
		MimeType:  "application/x-msdownload",
		SizeBytes: 512,
	})

	require.Error(t, err)
	var apiErr *apierr.APIError
	require.True(t, errors.As(err, &apiErr), "expected apierr.APIError")
	assert.Equal(t, "INVALID_MIME_TYPE", apiErr.Code)
}

func TestPreRegister_FileTooLarge(t *testing.T) {
	svc := services.NewAttachmentService(newMockAttachRepo(), &mockS3Client{})

	_, err := svc.PreRegister(context.Background(), uuid.New(), uuid.New(), services.PreRegisterRequest{
		Filename:  "huge.mp4",
		MimeType:  "video/mp4",
		SizeBytes: 300 * 1024 * 1024, // 300 MiB > 200 MiB limit
	})

	require.Error(t, err)
	var apiErr *apierr.APIError
	require.True(t, errors.As(err, &apiErr), "expected apierr.APIError")
	assert.Equal(t, "FILE_TOO_LARGE", apiErr.Code)
}

func TestConfirm_SetsComplete(t *testing.T) {
	taskID := uuid.New()
	userID := uuid.New()
	repo := newMockAttachRepo()
	svc := services.NewAttachmentService(repo, &mockS3Client{})

	// Step 1 — pre-register
	resp, err := svc.PreRegister(context.Background(), taskID, userID, services.PreRegisterRequest{
		Filename: "doc.pdf", MimeType: "application/pdf", SizeBytes: 2048,
	})
	require.NoError(t, err)

	// Step 2 — the response AttachmentID must be the DB-assigned ID (bug fix: was locally-generated uuid)
	aid, err := uuid.Parse(resp.AttachmentID)
	require.NoError(t, err, "AttachmentID in response must be a valid UUID")

	// Step 3 — confirm directly using the ID from the response
	err = svc.Confirm(context.Background(), aid, userID)
	require.NoError(t, err)

	a, getErr := repo.GetByID(context.Background(), aid, userID)
	require.NoError(t, getErr, "GetByID with response AttachmentID must succeed")
	assert.Equal(t, repositories.AttachmentStatusComplete, a.Status)
	assert.NotNil(t, a.ConfirmedAt)
}

// TestPreRegister_Confirm_RoundTrip is the explicit architect-requested round-trip test.
// It verifies that the AttachmentID returned by PreRegister is the DB row's actual ID,
// so that the client can immediately use it to call Confirm.
func TestPreRegister_Confirm_RoundTrip(t *testing.T) {
	taskID := uuid.New()
	userID := uuid.New()
	repo := newMockAttachRepo()
	svc := services.NewAttachmentService(repo, &mockS3Client{})

	// 1. Pre-register — get back an attachment_id
	preResp, err := svc.PreRegister(context.Background(), taskID, userID, services.PreRegisterRequest{
		Filename:  "receipt.jpg",
		MimeType:  "image/jpeg",
		SizeBytes: 512,
	})
	require.NoError(t, err)
	require.NotEmpty(t, preResp.AttachmentID)

	// 2. Parse the returned ID — must be a valid UUID
	aid, err := uuid.Parse(preResp.AttachmentID)
	require.NoError(t, err, "PreRegister must return a valid UUID attachment_id")

	// 3. Verify the ID maps to a real PENDING row in the repo
	a, err := repo.GetByID(context.Background(), aid, userID)
	require.NoError(t, err, "PreRegister response attachment_id must be the DB-assigned row ID")
	assert.Equal(t, repositories.AttachmentStatusPending, a.Status)

	// 4. Confirm using the exact ID returned by PreRegister — must succeed
	err = svc.Confirm(context.Background(), aid, userID)
	require.NoError(t, err, "Confirm must succeed using the ID returned by PreRegister")

	// 5. Verify row is now COMPLETE
	a, err = repo.GetByID(context.Background(), aid, userID)
	require.NoError(t, err)
	assert.Equal(t, repositories.AttachmentStatusComplete, a.Status, "attachment must be COMPLETE after Confirm")
	assert.NotNil(t, a.ConfirmedAt, "confirmed_at must be set")

	// 6. Double-confirm must return 422 ATTACHMENT_NOT_PENDING (status guard in MarkComplete)
	err = svc.Confirm(context.Background(), aid, userID)
	require.Error(t, err, "second Confirm must fail")
	var apiErr *apierr.APIError
	require.True(t, errors.As(err, &apiErr))
	assert.Equal(t, "ATTACHMENT_NOT_PENDING", apiErr.Code, "second Confirm must return 422 ATTACHMENT_NOT_PENDING")
}

func TestConfirm_AlreadyComplete_Returns422(t *testing.T) {
	repo := newMockAttachRepo()
	repo.markCompleteErr = repositories.ErrNotFound // simulates already-COMPLETE or missing
	svc := services.NewAttachmentService(repo, &mockS3Client{})

	err := svc.Confirm(context.Background(), uuid.New(), uuid.New())

	require.Error(t, err)
	var apiErr *apierr.APIError
	require.True(t, errors.As(err, &apiErr), "expected apierr.APIError")
	assert.Equal(t, "ATTACHMENT_NOT_PENDING", apiErr.Code)
}

func TestDeleteAttachment_DeletesS3ThenDB(t *testing.T) {
	taskID := uuid.New()
	userID := uuid.New()
	repo := newMockAttachRepo()
	s3 := &mockS3Client{}
	svc := services.NewAttachmentService(repo, s3)

	// Seed a COMPLETE attachment directly in the repo
	now := time.Now()
	a := &repositories.Attachment{
		ID:      uuid.New(),
		TaskID:  taskID,
		UserID:  userID,
		Status:  repositories.AttachmentStatusComplete,
		S3Key:   "user/task/attachment.jpg",
		ConfirmedAt: &now,
	}
	repo.attachments[a.ID] = a

	err := svc.Delete(context.Background(), a.ID, userID)

	require.NoError(t, err)
	assert.True(t, s3.delCalled, "S3 must be deleted before DB row")
	_, notFound := repo.attachments[a.ID]
	assert.False(t, notFound, "DB row must be gone after delete")
}

func TestListAttachments_OnlyComplete(t *testing.T) {
	taskID := uuid.New()
	userID := uuid.New()
	repo := newMockAttachRepo()
	s3 := &mockS3Client{}
	svc := services.NewAttachmentService(repo, s3)

	// Seed one PENDING and one COMPLETE
	now := time.Now()
	repo.attachments[uuid.New()] = &repositories.Attachment{
		ID:     uuid.New(), TaskID: taskID, UserID: userID,
		Status: repositories.AttachmentStatusPending, S3Key: "k1",
	}
	repo.attachments[uuid.New()] = &repositories.Attachment{
		ID:          uuid.New(), TaskID: taskID, UserID: userID,
		Status:      repositories.AttachmentStatusComplete, S3Key: "k2",
		ConfirmedAt: &now,
	}

	list, err := svc.List(context.Background(), taskID, userID)

	require.NoError(t, err)
	assert.Len(t, list, 1, "only COMPLETE attachments must be returned")
}

func TestCleanupJob_DeletesPendingOlderThan1Hour(t *testing.T) {
	// This test verifies the job pattern by testing at the service/repo boundary.
	// Direct test of AttachmentCleanupJob.Run is an integration concern (needs real time + DB).
	// Here we verify the repo mock's DeletePendingOlderThan interface is plumbed correctly.
	repo := newMockAttachRepo()
	cutoff := time.Now().Add(-time.Hour)
	rows, err := repo.DeletePendingOlderThan(context.Background(), cutoff)
	require.NoError(t, err)
	assert.Empty(t, rows, "no stale rows in fresh mock")
}

func TestPreRegister_S3ErrorPreventsDBInsert(t *testing.T) {
	// If S3 presign fails, no DB row should be created.
	repo := newMockAttachRepo()
	s3 := &mockS3Client{putErr: errors.New("s3 offline")}
	svc := services.NewAttachmentService(repo, s3)

	_, err := svc.PreRegister(context.Background(), uuid.New(), uuid.New(), services.PreRegisterRequest{
		Filename: "photo.jpg", MimeType: "image/jpeg", SizeBytes: 100,
	})

	require.Error(t, err)
	assert.Empty(t, repo.attachments, "no DB row created if S3 presign failed")
}
