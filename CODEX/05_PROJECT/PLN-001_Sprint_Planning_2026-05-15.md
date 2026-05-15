---
id: PLN-001
title: "Architect Sprint Planning — Task Nibbles (2026-05-15)"
type: planning
status: DRAFT
owner: architect
agents: [architect]
tags: [project-management, sprint-planning, architect]
related: [BCK-001, BCK-002, SPR-001-BE, SPR-002-BE, AUD-001-BE]
created: 2026-05-15
updated: 2026-05-15
version: 1.0.0
---

> **BLUF:** SPR-001-BE is audited and approved. The one human-gated action is the `develop` merge + staging deploy. SPR-002-BE is unblocked and ready to assign. SPR-001-MB remains blocked until the staging backend is live. Backend sprints 3–6 each unblock sequentially. No contract changes are required. This document records the Architect's full state assessment and sprint sequencing decisions.

# Architect Sprint Planning — 2026-05-15

---

## 1. Project State Assessment

### 1.1 Git / Branch State

| Item | State |
|:-----|:------|
| Active branch | `feature/B-001-backend-scaffold` |
| Last commit | `6d73d0e` — post-SPR-001-BE staging ops chore |
| `develop` branch | At Day-0 commit `14c1543` — **SPR-001-BE has NOT been merged** |
| `main` | At Day-0 commit — clean |

**Critical gating action required by Human:**
> Merge `feature/B-001-backend-scaffold` → `develop`, then run `fly deploy` from `backend/` and confirm `GET /health` returns 200 on `task-nibbles-api-staging.fly.dev`. This resolves AUD-001-BE Finding #2 and formally closes SPR-001-BE.

---

### 1.2 Sprint Status Ledger

| Sprint | Track | Status | Notes |
|:-------|:------|:-------|:------|
| SPR-001-BE | Backend | ✅ AUDITED (APPROVED_WITH_NOTES) | Awaiting Human merge to `develop` + staging deploy |
| SPR-002-BE | Backend | 🔴 READY TO ASSIGN | Blocked by merge gate above only; code not started |
| SPR-003-BE | Backend | 🔒 BLOCKED | Blocked by SPR-002-BE audit |
| SPR-004-BE | Backend | 🔒 BLOCKED | Blocked by SPR-002-BE audit |
| SPR-005-BE | Backend | 🔒 BLOCKED | Blocked by SPR-003-BE + SPR-004-BE |
| SPR-006-OPS | OPS | 🔒 BLOCKED | Blocked by all backend sprints |
| SPR-001-MB | Mobile | 🔒 BLOCKED | Blocked by staging backend being live |
| SPR-002-MB | Mobile | 🔒 BLOCKED | Blocked by SPR-001-MB + SPR-002-BE |
| SPR-003-MB | Mobile | 🔒 BLOCKED | Blocked by SPR-003-BE + SPR-002-MB |
| SPR-004-MB | Mobile | 🔒 BLOCKED | Blocked by SPR-004-BE + SPR-003-MB |
| SPR-005-MB | Mobile | 🔒 BLOCKED | Blocked by SPR-005-BE + SPR-004-MB |

---

### 1.3 Codebase Reality vs. BCK-001

All BCK items B-001 through B-037 (SPR-001-BE scope) are **DONE** per AUD-001-BE.

**What exists in `backend/` today:**

| Layer | Files Present | Missing (SPR-002-BE scope) |
|:------|:-------------|:--------------------------|
| Migrations | `0001`–`0005` | `0006_create_recurring_rules`, `0007_create_tasks` |
| SQL Queries | `auth.sql`, `users.sql`, `password_reset.sql`, `gamification.sql` (2 queries) | `tasks.sql`, `recurring_rules.sql`; more gamification queries |
| Handlers | `auth_handler.go`, `health_handler.go` | `task_handler.go` |
| Services | `auth_service.go`, `email_service.go` | `task_service.go`, `gamification_service.go` (full engine) |
| Repositories | `auth_repository.go` | `task_repository.go` |
| Jobs | Empty directory | `nightly_cron.go` (cron bootstrap) |
| S3 client | Empty directory | `s3/client.go` (SPR-003-BE scope — do not touch in SPR-002-BE) |

**Key observation for SPR-002-BE developer:** Migration `0005_create_gamification_state.sql` already exists. Do NOT recreate it. The `gamification.sql` file has `CreateGamificationState` and `GetGamificationState` — extend this file with update queries needed for task completion.

---

### 1.4 BCK-002 (Architect Backlog) Reconciliation

The BCK-002 document was authored before blueprints, contracts, and agent docs were populated. Those were completed in a prior session. BCK-002 needs a status sweep.

**Items that are actually ✅ Done (incorrectly still showing `[ ] Open`):**

| ID | Task |
|:---|:-----|
| A-007 through A-012 | All Blueprint + Contract docs (BLU-002, BLU-002-SD, BLU-003, BLU-004, CON-001, CON-002) |
| A-013, A-014 | AGT-002-BE and AGT-002-MB agent boot docs |
| A-015 through A-025 | All 11 sprint documents (SPR-001-BE through SPR-006-OPS) |
| A-026 | SPR-001-BE Audit (AUD-001-BE filed, APPROVED_WITH_NOTES) |

**Items correctly still open:** A-027 through A-045.

---

## 2. Sprint Sequencing Decision

### 2.1 Backend Critical Path

```
SPR-001-BE (DONE)
      ↓
SPR-002-BE (Task CRUD)
      ↓ (after audit)
SPR-003-BE (Attachments)  ←──── can run in parallel ────→  SPR-004-BE (Gamification)
      ↓
SPR-005-BE (Recurring Tasks)
      ↓
SPR-006-OPS (Fly.io Deploy)
```

> [!IMPORTANT]
> SPR-003-BE and SPR-004-BE have **no code dependency on each other** and can be assigned simultaneously after SPR-002-BE audit passes. Assign to the same or two separate developer sessions.

### 2.2 Mobile Can Start in Parallel with SPR-002-BE

```
Staging deploy live → SPR-001-MB (Mobile Scaffold + Auth) — runs in parallel with SPR-002-BE
```

Mobile Sprint 1 only needs the `/auth/*` endpoints from SPR-001-BE. It does not wait for SPR-002-BE.

### 2.3 Next Human Actions (Priority Order)

| Priority | Action | Unblocks |
|:---------|:-------|:---------|
| 🔴 P0 | Merge `feature/B-001-backend-scaffold` → `develop` (GitHub PR) | SPR-002-BE branch fork |
| 🔴 P0 | `fly deploy` from `backend/` on `develop` + verify `/health` 200 | SPR-001-MB; closes AUD-001-BE Finding #2 |
| 🟡 P1 | Boot Backend Developer Agent with `AGT-002-BE` → assign SPR-002-BE | Task CRUD track |
| 🟡 P1 | (After staging live) Boot Mobile Developer Agent → assign SPR-001-MB | Mobile track |

---

## 3. SPR-002-BE: Developer Agent Hand-Off Brief

### Status: READY TO ASSIGN ✅

**Branch:** Fork `feature/B-010-task-crud` from `develop` (after merge above).

**Reading order for developer:**
1. `AGT-002-BE_Backend_Developer_Agent.md` — boot doc (mandatory)
2. `CON-002_API_Contract.md` §3 — Task routes (exact schemas)
3. `BLU-002_Database_Schema.md` §§3.4–3.5, 3.7 — recurring_rules, tasks, gamification_state
4. `SPR-002-BE_Task_CRUD_Backend.md` — tasks and exit criteria

---

### Critical Implementation Constraints

> [!IMPORTANT]
> These are non-negotiable contract requirements. Deviation triggers a DEF- report.

**1. Migration numbering**
Next migrations: `0006_create_recurring_rules.sql`, `0007_create_tasks.sql`.
Do NOT use 0005 — it is taken by `gamification_state` from SPR-001-BE.

**2. Gamification state row on register**
Add `tx.CreateGamificationState()` call inside `auth_service.go → Register()` in the **same DB transaction** as the `users` INSERT. The table and query already exist — this is purely a service call addition.

**3. `is_overdue` is computed, never stored**
The `tasks` table must NOT have an `is_overdue` column. Calculate in the repository layer:
```go
t.IsOverdue = t.Status == TaskStatusPending &&
              t.EndAt != nil &&
              t.EndAt.Before(time.Now().UTC())
```

**4. `sort_order` default**
New task gets `MAX(sort_order) + 1` for the user (or 1 if no tasks exist), not 0. Use a subquery or explicit query.

**5. Gamification scope (partial — SPR-002-BE only)**
Implement `GamificationService.OnTaskCompleted(ctx, userID)` that:
- Fetches `gamification_state` for user
- Increments `streak_count` if `last_active_date != today UTC`
- Updates `last_active_date = today`
- Applies `+5` to `tree_health_score` (cap at 100)
- Sets `has_completed_first_task = true` on first completion
- Returns `GamificationDelta` with `badges_awarded: []Badge{}` (empty slice, **not nil**)
- Does **NOT** evaluate any badges — that is SPR-004-BE scope

**6. CANCELLED status**
Sets `cancelled_at = now()`. Zero gamification impact — do NOT call `GamificationService`.

**7. Cron bootstrap**
Create `internal/jobs/nightly_cron.go` with the job scheduler initialized in `main.go`. No actual job implementations yet — establish the pattern. Use `go-co-op/gocron` (already in go.mod or add it if not).

**8. New SQL queries needed (`db/queries/gamification.sql`)**
```sql
-- name: UpdateGamificationStateOnComplete :one
UPDATE gamification_state
SET streak_count              = $2,
    last_active_date          = $3,
    tree_health_score         = $4,
    has_completed_first_task  = $5,
    updated_at                = now()
WHERE user_id = $1
RETURNING *;
```

---

### Exit Criteria Checklist (from SPR-002-BE)

- [ ] `GET /tasks` returns paginated list with all filter/sort params working
- [ ] `POST /tasks` creates task; returns 422 VALIDATION_ERROR on missing title
- [ ] `GET /tasks/:id` returns single task with `is_overdue` field
- [ ] `PATCH /tasks/:id` updates fields; CANCELLED sets `cancelled_at`
- [ ] `DELETE /tasks/:id` hard-deletes task row
- [ ] `POST /tasks/:id/complete` sets `completed_at`, returns `gamification_delta`
- [ ] `PATCH /tasks/:id/sort-order` reorders task
- [ ] `gamification_state` row created on register (same transaction)
- [ ] `is_overdue` absent from `tasks` DB columns
- [ ] `go test ./...` passes, ≥ 70% coverage on task handlers + services

---

## 4. SPR-001-MB: Mobile Developer Agent Hand-Off Brief

### Status: PENDING STAGING DEPLOY ⏳

Mobile Sprint 1 begins immediately after `fly deploy` confirms staging is live.

**Branch:** `feature/M-001-mobile-scaffold` (fork from `develop`)

**Staging base URL:** `https://task-nibbles-api-staging.fly.dev`

**Reading order for developer:**
1. `AGT-002-MB_Mobile_Developer_Agent.md` — full boot doc
2. `BLU-004_Frontend_Architecture.md` — Flutter architecture
3. `CON-001_Transport_Contract.md` — base URLs, auth header, error envelope
4. `CON-002_API_Contract.md` §1 — auth routes (scope of SPR-001-MB)
5. `SPR-001-MB_Mobile_Scaffold_and_Auth.md` — tasks and exit criteria

---

## 5. Open Questions for Human

> [!IMPORTANT]
> The following require Human input before the Architect can proceed.

| # | Question | Impact |
|:--|:---------|:-------|
| Q-001 | Has the `feature/B-001-backend-scaffold` branch been merged to `develop`? | SPR-002-BE cannot branch until this is done |
| Q-002 | Has `fly deploy` been run on staging? What does `/health` return? | Required to close AUD-001-BE Finding #2; gates SPR-001-MB |
| Q-003 | Is S3 bucket `task-nibbles-attachments` provisioned yet? (BCK-002 A-040) | Required before SPR-003-BE can start |

---

## 6. Architect Decisions Log

| # | Decision | Rationale |
|:--|:---------|:----------|
| D-001 | SPR-003-BE and SPR-004-BE run in parallel after SPR-002-BE audit | No code dependency between attachments and gamification engine |
| D-002 | Badge evaluation deferred to SPR-004-BE; SPR-002-BE delivers partial gamification only | Keeps sprint 2 properly scoped |
| D-003 | SPR-001-MB unblocked by staging deploy, not SPR-002-BE | Mobile auth only needs `/auth/*` endpoints (SPR-001-BE) |
| D-004 | No contract changes required for any upcoming sprint | CON-001 and CON-002 are complete and cover all remaining route implementations |
| D-005 | gamification_state 0005 migration is NOT in SPR-002-BE scope — it already exists | Developer must be aware to avoid migration conflict |

---

> *This document is the Architect's official planning record for the 2026-05-15 planning session. Next planning session triggers when SPR-002-BE audit is complete.*
