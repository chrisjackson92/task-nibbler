---
id: PLN-002
title: "Architect Sprint Planning — Task Nibbles (2026-05-15, Session 2)"
type: planning
status: APPROVED
owner: architect
agents: [architect]
tags: [project-management, sprint-planning, architect]
related: [BCK-001, PLN-001, SPR-007-BE, SPR-004-MB, SPR-005-MB]
created: 2026-05-15
updated: 2026-05-15
version: 1.0.0
---

> **BLUF:** All 6 BE sprints and 3 MB sprints are merged. Staging is live, CI/CD is wired. Three sprints remain for MVP completeness: **SPR-007-BE** (gamification nightly cron, ~1 day) and **SPR-004-MB** + **SPR-005-MB** (gamification UI + recurring task UI, ~8 days combined). SPR-007-BE and SPR-004-MB run in parallel. After both pass audit, SPR-005-MB runs. Production deploy follows.

# Architect Sprint Planning — Session 2 (2026-05-15)

---

## 1. Project State

### 1.1 Infrastructure

| Item | State |
|:-----|:------|
| Staging URL | `https://task-nibbles-api-staging.fly.dev` ✅ live |
| `/health` | `{"db":"ok","status":"ok","version":"1.0.0"}` ✅ |
| Migrations | 14 applied (0001–0014) ✅ |
| CI/CD | `develop` → staging auto-deploy ✅ |
| CI/CD | `main` → production (requires reviewer approval) ✅ |
| GitHub Secrets | `FLY_STAGING_API_TOKEN`, `FLY_PROD_API_TOKEN` ✅ |
| GitHub Environment | `production` with Required Reviewer: `chrisjackson92` ✅ |
| Production deploy | **Not yet run** — manual step after MVP sprints |

### 1.2 Sprint Status Ledger

| Sprint | Track | Status | Audit |
|:-------|:------|:-------|:------|
| SPR-001-BE | Backend | ✅ MERGED | AUD-001-BE |
| SPR-002-BE | Backend | ✅ MERGED | AUD-002-BE |
| SPR-003-BE | Backend | ✅ MERGED | AUD-003-BE |
| SPR-004-BE | Backend | ✅ MERGED | AUD-004-BE |
| SPR-005-BE | Backend | ✅ MERGED | AUD-006-BE |
| SPR-006-OPS | OPS | ✅ MERGED | AUD-008-OPS |
| SPR-001-MB | Mobile | ✅ MERGED | AUD-005-MB |
| SPR-002-MB | Mobile | ✅ MERGED | AUD-007-MB |
| SPR-003-MB | Mobile | ✅ MERGED | AUD-009-MB |
| **SPR-007-BE** | Backend | 🟢 READY | — pending |
| **SPR-004-MB** | Mobile | 🟢 READY | — pending |
| **SPR-005-MB** | Mobile | 🟢 READY (after SPR-004-MB) | — pending |

### 1.3 `develop` Head

```
f31017e  docs(codex): refresh sprint statuses + commit BE handoff [A-056]
cb2f9d5  merge(SPR-003-MB): Mobile attachments [AUD-009-MB ✅]
fa4c434  fix(ops): mig-0013 drop StatementBegin + CAST/INTERVAL [TRB-005,TRB-006]
5864f24  fix(ops): release_command 'migrate' not '/api migrate' [TRB-004]
```

---

## 2. Sprint Sequencing

### 2.1 Execution Graph

```
develop (now)
    ├── SPR-007-BE  ←─ PARALLEL ──────────────────── 1 day
    │   [B-063 gam nightly cron]
    │
    └── SPR-004-MB  ←─ PARALLEL ──────────────────── 5 days
        [M-030..M-035 gamification UI + Rive]
            │
            └── SPR-005-MB  ←─ SEQUENTIAL ─────────── 3 days
                [M-036..M-039 recurring task UI]
                    │
                    └── Production deploy (OPS — human gated)
```

> [!IMPORTANT]
> **SPR-007-BE and SPR-004-MB have no dependency on each other.** Assign to BE and MB agents simultaneously. Do not wait for one before starting the other.

### 2.2 Total Remaining Estimate

| Sprint | Days | Parallel? |
|:-------|:-----|:----------|
| SPR-007-BE | 1 | Yes (with SPR-004-MB) |
| SPR-004-MB | 5 | Yes (with SPR-007-BE) |
| SPR-005-MB | 3 | No (after SPR-004-MB audit) |
| **Total wall-clock** | **~8 days** (5 + 3, with SPR-007-BE inside the 5) | |

---

## 3. SPR-007-BE Hand-Off Brief

### Status: READY TO ASSIGN ✅

**Assignment:** Backend Developer Agent  
**Branch:** `feature/B-063-gamification-nightly-cron` (fork from `develop`)  
**Estimated:** 1 day

**Reading order:**
1. `AGT-002-BE_Backend_Developer_Agent.md` — boot doc
2. `backend/internal/jobs/` — understand existing job pattern
3. `backend/internal/services/gamification_service.go` — confirm `ApplyNightlyDecay` + `ApplyOverduePenalty` signatures
4. `SPR-007-BE_Gamification_Nightly_Cron.md` — tasks and exit criteria

**Key constraints:**
- New file: `internal/jobs/gamification_nightly_job.go`
- Interface: `GamificationServicer` (jobs package) with two methods only
- Registration: `00:30 UTC` in `main.go` gocron scheduler
- Error handling: decay error does NOT abort penalty (two separate checks, no early return)
- No schema migrations required

---

## 4. SPR-004-MB Hand-Off Brief

### Status: READY TO ASSIGN ✅

**Assignment:** Mobile Developer Agent  
**Branch:** `feature/M-030-gamification-ui` (fork from `develop`)  
**Estimated:** 5 days

**Reading order:**
1. `AGT-002-MB_Mobile_Developer_Agent.md` — boot doc
2. `PRJ-001_product_vision_and_features.md` §5.5 — full gamification spec
3. `BLU-004_Frontend_Architecture.md` §§7–8 — Rive specs + home screen layout
4. `BLU-002-SD_Seed_Data_Reference.md` §3 — badge catalog (14 badges, triggers)
5. `CON-002_API_Contract.md` — `/gamification/state`, `/gamification/badges` routes
6. `SPR-004-MB_Gamification_Mobile.md` — tasks and exit criteria

**Key constraints:**
- Wire hero section to real `GET /gamification/state` (SPR-001-MB had a placeholder)
- Rive files: If `sprite.riv` / `tree.riv` absent → animated colour-block placeholder; DO NOT block sprint
- `applyDelta()` called after task completion (NOT a new `loadState()` network call)
- Badge overlay auto-dismisses after 4 seconds
- `GamificationBadgeAwarded` state triggers overlay — state flows through BLoC, not callback

**Staging endpoint:** `https://task-nibbles-api-staging.fly.dev/api/v1/gamification/state`

---

## 5. SPR-005-MB Hand-Off Brief

### Status: READY (starts after SPR-004-MB audit passes) ⏳

**Assignment:** Mobile Developer Agent (same session or new session after SPR-004-MB audit)  
**Branch:** `feature/M-036-recurring-task-ui` (fork from `develop`)  
**Estimated:** 3 days

**Reading order:**
1. `AGT-002-MB_Mobile_Developer_Agent.md` — boot doc
2. `PRJ-001_product_vision_and_features.md` §5.4 — recurring task edit scope spec
3. `CON-002_API_Contract.md` §3 — `?scope=this_only` / `?scope=this_and_future` on PATCH/DELETE
4. `SPR-005-MB_Recurring_Tasks_Mobile.md` — tasks and exit criteria

**Key constraints:**
- Edit scope dialog shown BEFORE navigating to form — for recurring task instances only
- `?scope=` query param on EVERY PATCH/DELETE of a recurring instance (not just edits)
- Custom RRULE field shows inline error from API `422 INVALID_RRULE`
- NEW recurring tasks (not editing) do NOT show scope dialog

---

## 6. Post-MVP Sprint Horizon

After SPR-007-BE + SPR-004-MB + SPR-005-MB are merged and audited, the project enters the production phase. The following items are on the post-MVP horizon (not scoped into a sprint yet):

| Item | Priority | Notes |
|:-----|:---------|:------|
| Production deploy (`fly deploy --app task-nibbles-api`) | 🔴 P0 | Requires human approval gate via GitHub Environments |
| Push notification sending (APNs + FCM via `device_tokens` table) | 🟡 P1 | `device_tokens` table exists (SPR-004-BE); sending endpoint not yet spec'd |
| App Store submission prep (screenshots, metadata, TestFlight) | 🟡 P1 | Human-gated |
| Rive `.riv` asset creation (if stubs used in SPR-004-MB) | 🟡 P1 | Depends on SPR-004-MB delivery choice |

---

## 7. Architect Decisions

| # | Decision | Rationale |
|:--|:---------|:----------|
| D-001 | SPR-007-BE runs in parallel with SPR-004-MB | Zero code dependency; no shared files; both branch from `develop` |
| D-002 | SPR-005-MB blocked on SPR-004-MB audit (not just merge) | SPR-005-MB's task form extends the same task form screen; audit may result in structural changes |
| D-003 | Proceed with Rive stubs if `.riv` files not present | SPR-004-MB doc already specifies placeholder policy; don't gate entire gamification sprint on asset files |
| D-004 | Production deploy is human-gated after all three sprints merged | CI/CD pipeline enforces the GitHub Environment protection rule |
| D-005 | No new BCK items added this session | All remaining MVP items were already in BCK-001; B-063 was pre-filed in AUD-006-BE |

---

> *This document supersedes the sprint sequencing in PLN-001, which reflected the pre-implementation state. All architecture, contracts, and blueprints remain unchanged. Next planning session triggers after SPR-005-MB audit is complete.*
