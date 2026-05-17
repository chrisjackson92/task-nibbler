---
id: PLN-003
title: "Architect Sprint Planning — Task Nibbles (2026-05-17)"
type: planning
status: APPROVED
owner: architect
agents: [architect]
tags: [project-management, sprint-planning, architect]
related: [BCK-001, BCK-002, PLN-002, SPR-008-MB, SPR-009-MB, AUD-013-MB, AUD-014-MB]
created: 2026-05-17
updated: 2026-05-17
version: 1.0.0
---

> **BLUF:** SPR-008-MB and SPR-009-MB are closed and audited. Two sprints remain: **SPR-010-MB** (production polish — push notifications opt-in, widget refinements, final APK) and one OPS task (production backend deploy approval). CON-002 requires an update to register 3 new endpoints from SPR-009-MB. The next developer agent assignment is SPR-010-MB.

# Architect Sprint Planning — 2026-05-17

---

## 1. Project State

### 1.1 Infrastructure

| Item | State |
|:-----|:------|
| Staging URL | `https://task-nibbles-api-staging.fly.dev` ✅ live |
| CI/CD | `main` → production (requires reviewer approval) ✅ |
| Migrations applied | 0001–0016 (staging) |
| Production deploy | ⏳ Pending Human approval (SPR-009-MB CI run) |
| Latest APK | `v1.2` (S3) — `v1.3` pending CI completion |

### 1.2 Sprint Status Ledger

| Sprint | Track | Status | Audit |
|:-------|:------|:-------|:------|
| SPR-001-BE | Backend | ✅ CLOSED | AUD-001-BE |
| SPR-002-BE | Backend | ✅ CLOSED | AUD-002-BE |
| SPR-003-BE | Backend | ✅ CLOSED | AUD-003-BE |
| SPR-004-BE | Backend | ✅ CLOSED | AUD-004-BE |
| SPR-005-BE | Backend | ✅ CLOSED | AUD-006-BE |
| SPR-006-OPS | OPS | ✅ CLOSED | AUD-008-OPS |
| SPR-007-BE | Backend | ✅ CLOSED | AUD-011-BE |
| SPR-001-MB | Mobile | ✅ CLOSED | AUD-005-MB |
| SPR-002-MB | Mobile | ✅ CLOSED | AUD-007-MB |
| SPR-003-MB | Mobile | ✅ CLOSED | AUD-009-MB |
| SPR-004-MB | Mobile | ✅ CLOSED | AUD-010-MB |
| SPR-005-MB | Mobile | ✅ CLOSED | AUD-012-MB |
| **SPR-008-MB** | Mobile | ✅ CLOSED | **AUD-013-MB** |
| **SPR-009-MB** | Mobile + BE | ✅ CLOSED | **AUD-014-MB** |
| **SPR-010-MB** | Mobile | 🟢 READY TO ASSIGN | — |

### 1.3 Remaining Backlog Items (MVP + Post-MVP)

| Item | Type | Priority |
|:-----|:-----|:---------|
| Production backend deploy (Human gated — approve CI run) | OPS | 🔴 P0 |
| CON-002 update (3 new SPR-009 routes) | ARCH-CODEX | 🔴 P0 |
| SPR-010-MB: production polish sprint | Mobile | 🟡 P1 |
| Push notifications opt-in (device token registration) | Mobile/BE | 🟡 P1 |
| App Store submission prep | OPS | 🟡 P1 |

---

## 2. Architect Actions Required (Before Next Sprint)

| ID | Action | Status |
|:---|:-------|:-------|
| A-NEW-001 | Update `CON-002` with 3 new SPR-009-MB endpoints | 🔴 Open — architect must do |
| A-NEW-002 | Update `BCK-001` with post-MVP items | 🟡 Open |
| A-NEW-003 | Update `BCK-002` to mark completed audit items | 🟡 Open |
| A-NEW-004 | MANIFEST.yaml update (register SPR-008-MB, SPR-009-MB, AUD-013-MB, AUD-014-MB, PLN-003) | 🟡 Open |

---

## 3. Next Sprint: SPR-010-MB

### Status: READY TO ASSIGN ✅

**Assignment:** Mobile Developer Agent  
**Estimated:** 3 days

### 3.1 Scope

| Task | Priority | Notes |
|:-----|:---------|:------|
| Push notification permission request on first launch | P1 | Use `permission_handler`; call `POST /device-tokens` if granted |
| Device token registration endpoint call | P1 | `POST /api/v1/device-tokens {token, platform}` — route not yet in BE |
| Empty state screens (task list empty, no badges yet) | P2 | Friendly empty states with CTA |
| Loading skeleton for task list | P2 | Shimmer while BLoC is loading |
| Companion health label display on hero section | P2 | Already partially in `_StreakColumn`; add full label |
| App icon + splash screen branding | P2 | Final branded assets |
| Production APK v1.3 build + S3 distribution | P0 | Must be last step |

> [!IMPORTANT]
> **Device token backend endpoint does not yet exist.** If the BE push notification endpoint is not ready, the mobile agent should implement the permission request and store the token locally (Hive), then call the API lazily when the key is available. Do NOT block the sprint on this.

### 3.2 Hand-Off Brief for Mobile Developer Agent

**Reading order:**
1. `AGT-002-MB_Mobile_Developer_Agent.md` — boot doc
2. `PRJ-001_product_vision_and_features.md` §4 — notification spec
3. `CON-002_API_Contract.md` — check if `/device-tokens` is registered (may not be)
4. `SPR-010-MB_Production_Polish.md` — tasks and exit criteria (to be created by Architect)
5. `SPR-009-MB_Companion_Selection_Profile_Expansion.md` — context on what was just built

**Key constraints:**
- Notification permission must be requested at the right moment (after onboarding, not on splash)
- Do not hardcode any backend URLs — use `ApiConfig` from existing DI setup
- All new screens must follow existing M3 theme (no ad-hoc colours)
- `flutter analyze` must pass with 0 errors before marking complete

> [!NOTE]
> The Architect will create `SPR-010-MB_Production_Polish.md` before assigning. This PLN document is the planning record; the SPR document is the agent handoff brief.

---

## 4. Parallel Push Notification Backend

> [!NOTE]
> If the mobile agent reaches the push notification feature and the backend endpoint is not available, the Backend Developer Agent should be assigned **SPR-008-BE** (device token registration + notification dispatch) in parallel. This is a one-day backend sprint.

### SPR-008-BE Scope (if needed in parallel)

| Task | Notes |
|:-----|:------|
| `device_tokens` table (already in DB from SPR-004-BE) | Confirm schema matches |
| `POST /api/v1/device-tokens` — upsert token for authenticated user | |
| `DELETE /api/v1/device-tokens/:token` — revoke on logout | |
| Service: APNs/FCM dispatch (stub OK for this sprint — real sending later) | |

---

## 5. Production Deploy Gate

> [!CAUTION]
> The production backend deploy for SPR-009-MB is pending the Human's approval in GitHub Actions. The Human must navigate to the Actions tab, find the latest `ci.yml` run on `main`, and approve the `deploy-production` job. This applies both the schema migrations AND the new endpoints.

**Required Human action:**
1. Go to `https://github.com/chrisjackson92/task-nibbler/actions`
2. Find the run for commit `3859ddf`
3. Approve the `deploy-production` environment

---

## 6. Architect Decisions

| # | Decision | Rationale |
|:--|:---------|:----------|
| D-001 | SPR-010-MB is the final mobile sprint before App Store prep | All core features now implemented; polish sprint completes the loop |
| D-002 | Push notification backend (SPR-008-BE) held in reserve | Only assign if mobile sprint reaches that feature; avoid speculative work |
| D-003 | CON-002 update is P0 architect task before any new BE sprint | Prevents contract drift accumulation |
| D-004 | No new architecture changes required | Companion system uses existing CustomPainter pattern; no Rive dependency introduced |
