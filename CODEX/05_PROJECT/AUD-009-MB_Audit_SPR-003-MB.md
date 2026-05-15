---
id: AUD-009-MB
title: "Architect Audit — SPR-003-MB Mobile Attachments"
type: audit
status: APPROVED
sprint: SPR-003-MB
pr_branch: feature/M-024-attachments
commit: af55ae4
auditor: architect
created: 2026-05-15
updated: 2026-05-15
---

> **BLUF:** SPR-003-MB **APPROVED**. 13-file sprint delivering a complete Pattern A attachment flow: pre-register → S3 PUT (separate Dio, no auth header) → confirm, with optimistic delete + 3-second undo, presigned URL never cached, offline-aware upload button, image/video viewer screens, and comprehensive cubit + widget tests. No findings. **Merge immediately.**

# Architect Audit — SPR-003-MB

---

## Audit Scope

| Item | Value |
|:-----|:------|
| Sprint | SPR-003-MB — Mobile Attachments |
| PR Branch | `feature/M-024-attachments` |
| Commit | `af55ae4` |
| Files Changed | 13 |
| Contracts Audited Against | CON-002 §4, BLU-003, BLU-004 (Pattern A S3 upload) |

---

## BCK / BCK-MB Tasks Delivered

| MB ID | Task | Status |
|:------|:-----|:-------|
| M-024 | `AttachmentRepository` — Pattern A upload, list, delete, download URL | ✅ PASS |
| M-025 | `AttachmentCubit` — state machine, undo delete timer, `PermissionChecker` typedef | ✅ PASS |
| M-026 | `AttachmentListWidget` — progress bar, thumbnail grid, offline guard | ✅ PASS |
| M-027 | `ImageViewerScreen` — presigned URL fetch on open (not stored) | ✅ PASS |
| M-028 | `VideoPlayerScreen` — presigned URL fetch on open (not stored) | ✅ PASS |
| M-029 | Tests — cubit + widget | ✅ PASS |

---

## AttachmentRepository Audit

| Check | Result |
|:------|:-------|
| Three-step Pattern A: `preRegister()` → `uploadToS3()` → `confirm()` | ✅ |
| S3 PUT uses separate `_s3Dio` (plain `Dio()`, no interceptors) | ✅ Critical — prevents `Authorization: Bearer` header reaching S3 presigned URL (would cause 403) |
| `Content-Type` and `Content-Length` headers set on S3 PUT | ✅ |
| `onSendProgress` callback threads upload progress to cubit | ✅ |
| `getDownloadUrl()` fetches fresh URL on every call — not cached | ✅ CON-002 §4 compliant |
| Client-side MIME type allow-list: JPEG, PNG, HEIC, WebP, MP4, MOV | ✅ |
| Client-side size guard: 200 MiB max | ✅ |
| All API error codes mapped to typed `AttachmentRepositoryException` | ✅ |
| `TASK_NOT_FOUND`, `ATTACHMENT_NOT_FOUND`, `ATTACHMENT_LIMIT`, `FILE_TOO_LARGE`, `INVALID_MIME_TYPE`, `ATTACHMENT_NOT_PENDING` | ✅ All 6 codes handled |

---

## AttachmentCubit State Machine Audit

```
AttachmentLoading
    ↓ loadAttachments()
AttachmentIdle(attachments)
    ↓ pickAndUpload()
UploadPicking → UploadPreRegistering → UploadingToS3(progress) → UploadConfirming → [reload → Idle]
    ↓ permission denied
AttachmentError (with preserved attachment list)
    ↓ scheduleDelete()
AttachmentIdle (optimistic removal) → [3s timer] → _commitDelete() → API DELETE
    ↓ cancelDelete()
loadAttachments() (restored)
```

| Check | Result |
|:------|:-------|
| All upload states carry `attachments` list → no UI flicker during upload | ✅ |
| `isClosed` guard before emitting `UploadingToS3` progress | ✅ prevents emit-after-close crash |
| `_deleteTimer?.cancel()` in `close()` — no timer leak | ✅ |
| `PermissionChecker` typedef injectable — tests pass `(_) async => true` to skip platform channel | ✅ |
| Permission denial → `AttachmentError` with current list preserved | ✅ |
| S3 upload failure → `AttachmentError` with current list preserved (not `Idle([])`) | ✅ |
| `getDownloadUrl()` returns `null` on error — callers handle gracefully | ✅ |

---

## UI / Integration Audit

| Check | Result |
|:------|:-------|
| `TaskDetailScreen` creates `AttachmentCubit` via `BlocProvider` with `Injection.instance.attachmentRepository` | ✅ |
| Upload FAB disabled when `ConnectivityCubit` reports offline | ✅ |
| `ImageViewerScreen` calls `cubit.getDownloadUrl()` on open — URL not stored in widget state | ✅ CON-002 §4 |
| `VideoPlayerScreen` same pattern | ✅ |
| `CachedNetworkImage` used for thumbnails | ✅ |

---

## Test Coverage Audit

| Test | Scenarios Covered |
|:-----|:------------------|
| `attachment_cubit_test.dart` | Load success, load error, upload full success path (4 state transitions), permission denied, picker cancelled, S3 failure, scheduleDelete + commit, scheduleDelete + cancel/undo | ✅ |
| `attachment_list_widget_test.dart` | Renders idle state, shows progress bar during upload, offline disables upload button | ✅ |

---

## Findings

**None.**

---

## Decision

**APPROVED — merge to `develop`.**
