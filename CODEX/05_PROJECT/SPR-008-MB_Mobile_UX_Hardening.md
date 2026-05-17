---
id: SPR-008-MB
title: "Sprint 008 — Mobile: Session Restore, Permissions, First Task Badge, Profile"
type: sprint
status: CLOSED
owner: architect
agents: [coder-mobile]
tags: [sprint, mobile, auth, permissions, gamification, profile]
related: [AGT-002-MB, CON-002, BLU-004, SPR-004-MB, SPR-005-MB, AUD-012-MB]
created: 2026-05-17
updated: 2026-05-17
version: 1.0.0
---

> **BLUF:** Post-MVP bug-fix and UX improvement sprint. Four independent quality-of-life fixes shipped in a single PR: (1) session restore on app open, (2) Android/iOS runtime permission requests for camera, gallery, notifications, and microphone, (3) first-task badge display, (4) settings screen with Edit Profile (timezone). CI passed; production APK v1.2 tagged and released to S3.

# SPR-008-MB — Mobile UX Hardening

---

## Sprint Goal

Resolve the four highest-priority user-reported issues before starting the companion/gamification visual expansion sprint.

---

## Sprint Scope

### Track: Mobile (Flutter)

| Task | Backlog Ref | Notes |
|:-----|:------------|:------|
| Session restore on app open — call `GET /auth/refresh` on cold start | M-010 (extend) | `AuthRestoreSessionRequested` event fires from `SplashScreen`; routes to tasks on success |
| Runtime permission requests — camera, gallery, notification, microphone | M-024 (extend) | `permission_handler` package; request on first use, graceful deny handling |
| Remove debug toast messages | — | Toast calls added during SPR-004-MB debugging removed |
| First task badge display in badge shelf | M-033 (extend) | `has_completed_first_task` flag from `/gamification/state` |
| Edit Profile screen — timezone picker (IANA TZDB) | M-010 (extend) | Calls `PATCH /users/me {timezone}` |
| Settings screen with logout, delete account, edit profile nav | M-010 | Full settings screen wired |
| Pull-to-refresh in task list (initial, incomplete — spinner issue noted for SPR-009) | M-014 (extend) | `RefreshIndicator` added; spinner dismiss bug deferred |

---

## Exit Criteria

- [x] App survives cold close/reopen without requiring re-login
- [x] Camera/Gallery upload requests runtime permission before picker opens
- [x] No debug toasts visible in release build
- [x] Badge shelf shows first-task badge in colour when `has_completed_first_task = true`
- [x] Edit Profile screen accessible from Settings; timezone change persists via API
- [x] `flutter analyze` passes (zero errors)
- [x] Production APK built and distributed via S3

---

## Delivery Notes

| Item | Value |
|:-----|:------|
| Commit | `7e11786` (feat(SPR-008-MB)) |
| Branch | `main` |
| APK Version | `v1.2` |
| Date Closed | 2026-05-17 |
| Audit | AUD-013-MB |

---

## Known Issues Deferred to SPR-009-MB

| Issue | Description |
|:------|:------------|
| Pull-to-refresh spinner | `firstWhere` on stream misses state if bloc completes before listener attaches |
| No "Remember Me" on login | Session restores but user can't opt out of persistence |
| No companion selection | Hero section has placeholder; sprite/tree selection not implemented |
| No display name field | Profile only exposes timezone |
| No change-password UI | Password can only be reset via forgot-password email |
