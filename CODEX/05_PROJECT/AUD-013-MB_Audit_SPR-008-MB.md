---
id: AUD-013-MB
title: "Architect Audit — SPR-008-MB: Mobile UX Hardening"
type: audit
status: APPROVED_WITH_NOTES
owner: architect
agents: [architect]
tags: [audit, mobile, sprint, ux, permissions, auth]
related: [SPR-008-MB, CON-002, AGT-002-MB]
created: 2026-05-17
updated: 2026-05-17
version: 1.0.0
---

> **BLUF:** SPR-008-MB is **APPROVED**. All five exit criteria pass. Session restore, runtime permissions, profile editing, and badge display are correctly implemented and aligned with CON-002 and BLU-004. Two deferred items (spinner bug, remember me) are formally captured in SPR-009-MB scope.

# Audit Report — SPR-008-MB

---

## Audit Method

Architect review of commit `7e11786` (feat(SPR-008-MB)) against:
- `CON-002_API_Contract.md` — route contracts
- `BLU-004_Frontend_Architecture.md` — mobile architecture spec
- `AGT-002-MB_Mobile_Developer_Agent.md` — agent standards

---

## Exit Criteria Checklist

| Criterion | Result | Evidence |
|:----------|:-------|:---------|
| Session restore on cold launch | ✅ Pass | `SplashScreen` fires `AuthRestoreSessionRequested`; `GET /auth/refresh` called on cold open |
| Camera/gallery runtime permissions | ✅ Pass | `permission_handler` requests on first use; graceful deny flow |
| No debug toasts in release | ✅ Pass | Toast debug calls removed from task completion path |
| First-task badge in colour | ✅ Pass | `has_completed_first_task` from `/gamification/state` drives badge shelf colour |
| Edit Profile (timezone) | ✅ Pass | `PATCH /users/me {timezone}` wired; IANA timezone picker in settings |
| `flutter analyze` passes | ✅ Pass | 0 errors, 0 warnings at time of release |

---

## Contract Compliance (CON-002)

| Route | Contract | Observed | Status |
|:------|:---------|:---------|:-------|
| `GET /auth/refresh` | Returns `{access_token, refresh_token, user}` | Called in `_onRestoreSession`, response parsed via `RefreshResponse.fromJson` | ✅ |
| `PATCH /users/me` | Accepts `{timezone}`, returns `{id, email, timezone, created_at}` | Confirmed wired in `EditProfileScreen` | ✅ |
| `GET /gamification/state` | Returns `has_completed_first_task` bool | Used to colour first-task badge in `BadgeShelfWidget` | ✅ |

---

## Findings

| # | Severity | Finding | Resolution |
|:--|:---------|:--------|:-----------|
| F-001 | Minor | Pull-to-refresh spinner hangs — `firstWhere` on stream can miss transition if bloc settles before listener attaches | Deferred to SPR-009-MB — fixed with Completer pattern |
| F-002 | Minor | No "Remember Me" option — all logins persist unconditionally | Deferred to SPR-009-MB — checkbox + memory-only token mode |
| F-003 | Info | Profile screen exposes timezone only; display name and password change not yet surfaced | Deferred to SPR-009-MB |

---

## Verdict

**APPROVED_WITH_NOTES** — All core functionality correct; deferred items formally captured.

| Item | Assigned To |
|:-----|:------------|
| F-001, F-002, F-003 | SPR-009-MB (complete) |
