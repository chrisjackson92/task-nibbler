---
id: SPR-003-BE
title: "Sprint 3 — Attachments Backend"
type: sprint
status: BLOCKED
assignee: coder
agent_boot: AGT-002-BE_Backend_Developer_Agent.md
sprint_number: 3
track: backend
estimated_days: 3
blocked_by: SPR-002-BE (must pass Architect audit)
related: [BLU-002, BLU-003, CON-002, GOV-008]
created: 2026-05-14
updated: 2026-05-14
---

> **BLUF:** Implement the full S3 attachment system using Pattern A (pre-register + confirm). By the end, files can be pre-registered, uploaded directly to S3, confirmed, listed, downloaded via presigned URL, and deleted. The nightly cleanup cron removes PENDING attachments older than 1 hour.

# Sprint 3-BE — Attachments Backend

---

## Pre-Conditions

- [ ] `SPR-002-BE` Architect audit PASSED
- [ ] AWS S3 bucket `task-nibbles-attachments` created (or dev bucket available)
- [ ] `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_S3_BUCKET` secrets set in Fly staging
- [ ] Read `CON-002_API_Contract.md` §4 (Attachment routes) in full
- [ ] Read `BLU-002_Database_Schema.md` §3.6 (task_attachments) in full
- [ ] Read `BLU-003_Backend_Architecture.md` §7 (S3 flow diagram) in full

---

## Exit Criteria

- [ ] `POST /tasks/:id/attachments` creates PENDING row + returns valid presigned S3 PUT URL (TTL 15 min)
- [ ] Client can PUT file directly to S3 using that URL without API involvement
- [ ] `POST /tasks/:id/attachments/:aid/confirm` sets `status = COMPLETE` and `confirmed_at`
- [ ] `GET /tasks/:id/attachments` returns only COMPLETE attachments
- [ ] `GET /tasks/:id/attachments/:aid/url` returns fresh presigned GET URL (TTL 60 min)
- [ ] `DELETE /tasks/:id/attachments/:aid` deletes S3 object and DB row synchronously
- [ ] Returns `422 ATTACHMENT_LIMIT` when task already has 10 COMPLETE attachments
- [ ] Returns `422 FILE_TOO_LARGE` when `size_bytes > 209,715,200` (200 MiB)
- [ ] Returns `422 INVALID_MIME_TYPE` for disallowed MIME types
- [ ] Nightly cleanup cron deletes PENDING rows older than 1 hour + corresponding S3 objects
- [ ] `go test ./...` passes, ≥ 70% attachment handler + service coverage

---

## Task List

| BCK ID | Task | Notes |
|:-------|:-----|:------|
| B-015 | AWS S3 client setup (aws-sdk-go-v2) | `internal/s3/client.go`; reads from env vars |
| B-016 | POST /tasks/:id/attachments — pre-register | Creates PENDING row; returns `attachment_id` + `upload_url` |
| B-017 | GET /tasks/:id/attachments — list COMPLETE | Only `status = COMPLETE` rows returned |
| B-018 | DELETE /tasks/:id/attachments/:aid | S3 DeleteObject first; then DB DELETE |
| B-019 | task_attachments DB schema + sqlc queries + migration | BLU-002 §3.6 |
| B-020 | File validation: MIME type allowlist + 200 MiB max | Applied in pre-register handler |
| B-042 | POST pre-register (replaces generic B-016 with Pattern A specifics) | S3 key = `{user_id}/{task_id}/{attachment_id}.{ext}` |
| B-043 | POST confirm — set status=COMPLETE | Returns 422 ATTACHMENT_NOT_PENDING if already complete |
| B-044 | GET /:aid/url — presigned GET URL | TTL 60 min; new URL each call |
| B-045 | Attachment cleanup cron job | goose Down must also clean; schedule in nightly_cron.go |

---

## Technical Notes

### S3 Key Format
```go
ext := filepath.Ext(req.Filename)      // e.g. ".jpg"
s3Key := fmt.Sprintf("%s/%s/%s%s",
    userID.String(),
    taskID.String(),
    attachmentID.String(),
    ext,
)
```

### Presigned PUT URL Generation
```go
presignClient := s3.NewPresignClient(s3Client)
putReq, _ := presignClient.PresignPutObject(ctx,
    &s3.PutObjectInput{
        Bucket:      aws.String(cfg.S3Bucket),
        Key:         aws.String(s3Key),
        ContentType: aws.String(req.MimeType),             // locks Content-Type
    },
    func(opts *s3.PresignOptions) {
        opts.Expires = 15 * time.Minute
    },
)
return putReq.URL, nil
```

### Attachment Limit Check
Before creating PENDING rows, count existing COMPLETE attachments:
```sql
-- db/queries/attachments.sql
SELECT COUNT(*) FROM task_attachments
WHERE task_id = $1 AND status = 'COMPLETE';
```
If count ≥ 10, return `apierr.ErrAttachmentLimit`.

### Cleanup Cron Query
```go
// internal/jobs/nightly_cron.go — AttachmentJob.CleanupPending
rows, err := attachmentRepo.DeletePendingOlderThan(ctx, time.Now().Add(-time.Hour))
for _, row := range rows {
    if err := s3Client.DeleteObject(ctx, row.S3Key); err != nil {
        slog.WarnContext(ctx, "s3 delete failed for orphaned attachment",
            "s3_key", row.S3Key, "error", err)
        // Do not re-insert — log and move on
    }
}
```

### Migration to Create
```
0008_create_task_attachments.sql
```

---

## Testing Requirements

| Test | Type | Required |
|:-----|:-----|:---------|
| `TestPreRegister_ReturnsPresignedURL` | Unit (mock S3) | ✅ |
| `TestPreRegister_AttachmentLimit` | Unit | ✅ |
| `TestPreRegister_InvalidMIME` | Unit | ✅ |
| `TestConfirm_SetsComplete` | Unit | ✅ |
| `TestConfirm_AlreadyComplete_Returns422` | Unit | ✅ |
| `TestListAttachments_OnlyComplete` | Integration | ✅ |
| `TestDeleteAttachment_DeletesS3AndDB` | Unit (mock S3) | ✅ |
| `TestCleanupCron_DeletesPendingOlderThan1Hour` | Unit | ✅ |

---

## Architect Audit Checklist

- [ ] `attachment_count` in `GET /tasks` response is correct (count of COMPLETE only)
- [ ] Presigned PUT URL `Content-Type` is locked to declared MIME type
- [ ] Confirm endpoint returns 422 (not 200) when called on COMPLETE attachment
- [ ] S3 delete called BEFORE DB delete (if S3 fails, row preserved — no ghost objects)
- [ ] PENDING rows older than 1 hour removed by cron — confirmed via manual `psql` check post-run
