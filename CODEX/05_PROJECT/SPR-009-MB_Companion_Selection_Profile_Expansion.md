---
id: SPR-009-MB
title: "Sprint 009 — Mobile + Backend: Companion Selection, 5-State Animations, Profile Expansion, UX Fixes"
type: sprint
status: CLOSED
owner: architect
agents: [coder-mobile, coder-backend]
tags: [sprint, mobile, backend, gamification, companion, profile, auth, ux]
related: [AGT-002-MB, AGT-002-BE, CON-002, BLU-004, BLU-002, SPR-008-MB, SPR-004-MB]
created: 2026-05-17
updated: 2026-05-17
version: 1.0.0
---

> **BLUF:** Full-stack sprint delivering the companion selection system (2 sprites × 2 trees with 5 health-state CustomPainter animations each), profile expansion (display name + change password), and two UX bug fixes (pull-to-refresh spinner + remember me). Backend migrations, new endpoints, and mobile UI all shipped in a single atomic commit. CI passed; awaiting Human approval for production deploy.

# SPR-009-MB — Companion Selection & Profile Expansion

---

## Sprint Goal

Give users a visible, animated companion that reflects their gamification health score, let them choose their sprite and tree, and provide a complete profile editing experience including display name and password management.

---

## Sprint Scope

### Track: Backend (Go + Gin + pgx)

| Task | Backlog Ref | Notes |
|:-----|:------------|:------|
| Migration `0015`: `display_name` column on `users` table | B-NEW | `VARCHAR(80) NULL` |
| Migration `0016`: `sprite_type`, `tree_type` columns on `gamification_state` | B-NEW | `VARCHAR(20) NOT NULL DEFAULT 'sprite_a'/'tree_a'` |
| `UserRepository.UpdateProfile()` — name + timezone PATCH | B-NEW | Replaces timezone-only method |
| `UserRepository.UpdatePasswordHash()` — bcrypt hash update | B-NEW | Used by change-password handler |
| `GamificationRepository.UpdateCompanion()` — persist sprite+tree selection | B-NEW | |
| `GamificationService.UpdateCompanion()` — service layer | B-NEW | Returns updated `GamificationStateResponse` |
| `GamificationStateResponse` — add `sprite_type`, `tree_type` fields | B-NEW | All state fetches return companion selection |
| `PATCH /users/me` — now accepts `display_name` (optional) + `timezone` | B-NEW | |
| `POST /auth/change-password` — verify current, bcrypt new, store | B-NEW | Returns 401 on current-password mismatch |
| `PATCH /gamification/companion` — persist sprite_type + tree_type | B-NEW | Validated: `oneof=sprite_a sprite_b` / `oneof=tree_a tree_b` |
| Test mocks: `UpdateCompanion` stub added to `mockGamifSvc` + `errGamifSvc` | — | CI fix commit `3859ddf` |

### Track: Mobile (Flutter)

| Task | Backlog Ref | Notes |
|:-----|:------------|:------|
| **Bug fix**: Pull-to-refresh spinner — `Completer`-based pattern (subscribe before dispatch) | M-014 (fix) | Replaces `firstWhere` stream approach that missed events |
| **Bug fix**: Remember Me checkbox on login screen (default ON) | M-007 (extend) | `persist` flag in `TokenStorage`; when OFF, refresh token is memory-only |
| `CompanionHealth` enum — 5 states from 20-pt score ranges (thriving/healthy/neutral/struggling/withering) | M-031 (extend) | Replaces 4-state `SpriteState` for rendering decisions |
| `SpriteAWidget` (Round Nibbler) — 5 health-state CustomPainter animations | M-031 | Bounce, glow, sparkle (thriving); tears (withering) |
| `SpriteBWidget` (Star Flare) — 5 health-state CustomPainter animations | M-031 | Rotating rays, pulse scale, dimming |
| `TreeAWidget` (Round Oak) — 5 health-state Crown animations | M-032 | 3-layer crown sway; rising/falling leaves |
| `TreeBWidget` (Crystal Pine) — 5 health-state tier animations | M-032 | Glowing tips; sparkle particles; muted for withering |
| `CompanionPickerScreen` — 2×2 animated grid (sprite A/B, tree A/B) | M-031 | Calls `PATCH /gamification/companion`; reloads state on save |
| `HeroSection` rewrite — renders selected sprite+tree; tap-to-pick; health bar uses `CompanionHealth` colour | M-013, M-031, M-035 | |
| `GamificationDetailScreen` — replaces old `SpriteWidget`/`TreeWidget` with new type-based widgets | M-030 | |
| `GamificationStateData` — add `spriteType`, `treeType` fields; `applyDelta()` carries them forward | — | Backwards-compatible (defaults to `sprite_a`/`tree_a`) |
| `GamificationRepository.updateCompanion()` — `PATCH /gamification/companion` | — | |
| `AuthUser` model — add `displayName` field | — | Null-safe; sourced from API `display_name` |
| `AuthRepository.updateProfile()` — name + timezone; `changePassword()` | — | `updateTimezone()` kept as alias |
| `EditProfileScreen` rewrite — display name field + change password section (independent forms) | M-010 (extend) | |
| `app_router.dart` — add `/gamification/companion` route | — | Provides `GamificationCubit` + `GamificationRepository` |

---

## Exit Criteria

- [x] Spinner dismisses after pull-to-refresh completes (no hanging indicator)
- [x] Remember Me checkbox visible on login; unchecked = session lost on app close
- [x] Hero section shows animated sprite and tree matching user's selection
- [x] Sprite and tree each have 5 visually distinct animations driven by health score
- [x] Tapping sprite or tree opens companion picker
- [x] Companion picker pre-selects current companion; Save persists via API
- [x] Edit Profile shows display name field and change password section
- [x] Change password: wrong current password returns error; new password requires ≥8 chars
- [x] `flutter analyze` passes (5 info hints, 0 errors, 0 warnings)
- [x] `go build ./...` passes
- [x] `go vet ./...` passes

---

## Delivery

| Item | Value |
|:-----|:------|
| Feature commit | `a60a645` (feat(SPR-009-MB)) |
| CI fix commit | `3859ddf` (fix(test): UpdateCompanion stubs) |
| Branch | `main` |
| Target APK | `v1.3` |
| Date Closed | 2026-05-17 |
| Audit | AUD-014-MB |
| Backend deploy | Pending Human approval in GitHub Actions |

---

## New API Endpoints (CON-002 Addendum)

| Method | Path | Auth | Notes |
|:-------|:-----|:-----|:------|
| `PATCH` | `/api/v1/gamification/companion` | Bearer | `{sprite_type, tree_type}` → returns `GamificationStateResponse` |
| `POST` | `/api/v1/auth/change-password` | Bearer | `{current_password, new_password}` |
| `PATCH` | `/api/v1/users/me` | Bearer | Now accepts optional `display_name` |

> [!IMPORTANT]
> CON-002 must be updated to register these three new routes in the next architect work session.
