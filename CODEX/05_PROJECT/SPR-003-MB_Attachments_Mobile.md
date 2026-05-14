---
id: SPR-003-MB
title: "Sprint 3 — Attachments Mobile"
type: sprint
status: BLOCKED
assignee: coder
agent_boot: AGT-002-MB_Mobile_Developer_Agent.md
sprint_number: 3
track: mobile
estimated_days: 4
blocked_by: SPR-003-BE (attachment endpoints live on staging) + SPR-002-MB (must pass audit)
related: [BLU-004, CON-002, PRJ-001]
created: 2026-05-14
updated: 2026-05-14
---

> **BLUF:** Implement the full media attachment UI — image and video picking, direct S3 upload via presigned URL (Pattern A), attachment list with thumbnails, full-screen image viewer, video playback, and swipe-to-delete with confirmation.

# Sprint 3-MB — Attachments Mobile

---

## Pre-Conditions

- [ ] `SPR-002-MB` Architect audit PASSED
- [ ] `SPR-003-BE` complete — attachment endpoints live on staging
- [ ] Read `CON-002_API_Contract.md` §4 (Attachment routes) in full
- [ ] Read `PRJ-001` §5.3 (Media Attachments — Pattern A flow) in full

---

## Exit Criteria

- [ ] `image_picker` opens camera and gallery picker from task detail screen
- [ ] Selected image/video: `POST /attachments` → direct PUT to returned S3 URL → `POST /confirm`
- [ ] Upload progress indicator shown during S3 PUT
- [ ] Attachment list in task detail shows thumbnails for images
- [ ] Full-screen image viewer on tap
- [ ] Video playback on tap (video_player)
- [ ] Swipe-to-delete: confirmation dialog → `DELETE /attachments/:aid`
- [ ] Graceful error: if S3 upload fails, attachment removed from UI and user informed
- [ ] Offline: attachment picker entry point disabled with tooltip when offline
- [ ] `fvm flutter test` passes, ≥ 70% AttachmentCubit coverage

---

## Task List

| BCK ID | Task | Notes |
|:-------|:-----|:------|
| M-024 | image_picker integration (camera + gallery) | Permission handling for iOS/Android |
| M-025 | Full Pattern A upload: pre-register → S3 PUT → confirm | Linear state: Idle → Picking → Uploading → Confirming → Done |
| M-026 | Attachment list widget (thumbnails + MIME-type icons) | Image: cached_network_image or FadeInImage; video: placeholder icon |
| M-027 | Full-screen image viewer (InteractiveViewer for pinch-zoom) | Load from presigned GET URL |
| M-028 | Video playback screen (video_player package) | Controls: play/pause, scrub bar |
| M-029 | Swipe-to-delete (Dismissible widget) + confirmation dialog | Undo snackbar for 3 seconds before delete API call |

---

## Technical Notes

### Pattern A Upload State Machine (AttachmentCubit)

```dart
sealed class AttachmentUploadState {}
class UploadIdle extends AttachmentUploadState {}
class UploadPicking extends AttachmentUploadState {}
class UploadPreRegistering extends AttachmentUploadState {}
class UploadingToS3 extends AttachmentUploadState {
  final double progress;  // 0.0 – 1.0
}
class UploadConfirming extends AttachmentUploadState {}
class UploadComplete extends AttachmentUploadState {
  final Attachment attachment;
}
class UploadFailed extends AttachmentUploadState {
  final String message;
}
```

### Direct S3 PUT via Dio
The S3 presigned URL must be called via a **separate Dio instance** (no auth interceptor — S3 rejects the `Authorization: Bearer` header):

```dart
// attachment_repository.dart
final s3Dio = Dio();  // plain Dio, no interceptors

await s3Dio.put(
  uploadUrl,
  data: fileStream,
  options: Options(
    headers: {
      'Content-Type': mimeType,
      'Content-Length': sizeBytes,
    },
  ),
  onSendProgress: (sent, total) {
    cubit.emit(UploadingToS3(progress: sent / total));
  },
);
```

### Permission Handling
```dart
// In attachment_repository.dart before calling image_picker
final status = await Permission.photos.request();
if (status.isDenied) {
  throw const AttachmentPermissionDenied();
}
```

### Undo Snackbar Delete Pattern
```dart
// Show undo snackbar; only call DELETE after 3 seconds if not undone
Timer? deleteTimer;
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text('Attachment removed'),
    action: SnackBarAction(
      label: 'UNDO',
      onPressed: () { deleteTimer?.cancel(); },
    ),
  ),
);
deleteTimer = Timer(Duration(seconds: 3), () {
  context.read<AttachmentCubit>().confirmDelete(attachmentId);
});
```

### Presigned GET URL for Viewing
Call `GET /tasks/:id/attachments/:aid/url` just before opening the viewer — never cache the presigned URL (it expires in 60 min and is not safe to persist).

---

## Testing Requirements

| Test | Type | Required |
|:-----|:-----|:---------|
| `AttachmentCubit: upload success → UploadComplete state` | Unit (mock S3 Dio) | ✅ |
| `AttachmentCubit: S3 PUT fail → UploadFailed state` | Unit | ✅ |
| `AttachmentCubit: delete → calls API after 3s` | Unit | ✅ |
| `AttachmentList widget: shows thumbnail for image attachment` | Widget | ✅ |
| `AttachmentList widget: picker disabled when offline` | Widget | ✅ |

---

## Architect Audit Checklist

- [ ] S3 PUT uses a plain Dio instance (no `Authorization: Bearer` header sent to S3)
- [ ] Upload progress bar visible during S3 PUT
- [ ] Undo snackbar cancels deletion (Timer cancelled on UNDO tap)
- [ ] Presigned GET URL fetched fresh each time viewer opens — not stored in state
- [ ] Image viewer uses `InteractiveViewer` (pinch-to-zoom confirmed)
- [ ] Attachment picker disabled when `ConnectivityCubit` is offline
