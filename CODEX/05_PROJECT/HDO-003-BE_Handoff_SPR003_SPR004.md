---
id: HDO-003-BE
title: "Backend Developer Handoff — SPR-003-BE + SPR-004-BE"
type: handoff
status: AWAITING_AUDIT
sprint: [SPR-003-BE, SPR-004-BE]
branches:
  - feature/B-015-B-045-attachments
  - feature/B-031-B-054-gamification
commits:
  spr003: 2d8e2a8
  spr004: 87945b3
  develop: 39e4044
agent: backend-developer
auditor: architect
created: 2026-05-15
updated: 2026-05-15
version: 1.0.0
---

> **BLUF:** Both SPR-003-BE (Attachments) and SPR-004-BE (Gamification Engine) are implemented and ready for architect audit. Both sprint branches are based on `develop @ 39e4044` which contains the resolved AUD-002-BE remediation (already pushed). All tests pass. Build is clean. Two PRs need review before merging to `develop`.

# Backend Developer Handoff — SPR-003-BE + SPR-004-BE

---

## 1. Delivery Summary

| Attribute | SPR-003-BE | SPR-004-BE |
|:----------|:----------|:----------|
| Branch | `feature/B-015-B-045-attachments` | `feature/B-031-B-054-gamification` |
| Tip commit | `2d8e2a8` | `87945b3` |
| Base commit | `39e4044 (develop)` | `39e4044 (develop)` |
| Files changed | 10 (+1,261 lines) | 11 (+1,001 / -135 lines) |
| Tests | 9 new (all pass) | 9 new + 2 mock stubs (all pass) |
| Build | ✅ `go build ./...` clean | ✅ `go build ./...` clean |
| DoD met | ✅ All acceptance criteria from SPR-003-BE | ✅ All acceptance criteria from SPR-004-BE |

---

## 2. What Was Built

### 2.1. SPR-003-BE — Attachments Backend

**Pattern A upload flow:** client calls pre-register → gets presigned S3 PUT URL → uploads directly → calls confirm.

#### New files

| File | Description |
|:-----|:------------|
| `db/migrations/0008_create_task_attachments.sql` | `task_attachments` table (BLU-002 §3.6). Indexes: COMPLETE/task, PENDING cleanup, user. |
| `internal/s3client/client.go` | `Client` interface + `awsS3Client` (aws-sdk-go-v2). `PresignPutURL` (15-min TTL, Content-Type locked), `PresignGetURL` (60-min TTL), `DeleteObject`. |
| `internal/repositories/attachment_repository.go` | `AttachmentRepository` interface + pgx implementation. 7 methods: Create, GetByID, ListByTaskID, CountComplete, MarkComplete, Delete, DeletePendingOlderThan. |
| `internal/services/attachment_service.go` | Business logic: MIME allowlist (14 types), 200 MiB cap, 10-attachment limit. S3 presign before DB insert; Delete S3 before DB row (audit requirement). |
| `internal/handlers/attachment_handler.go` | 5 routes mounted at `/tasks/:id/attachments`. |
| `internal/jobs/nightly_cron.go` | `AttachmentCleanupJob`: DELETE PENDING rows older than 1hr from DB (RETURNING s3_key), then best-effort S3 deletes. |
| `internal/services/attachment_service_test.go` | 9 tests: MIME allowlist, file size cap, attachment limit, presign flow, confirm lifecycle, delete order, S3-failure-prevents-DB-insert. |

#### Modified files

| File | Change |
|:-----|:-------|
| `cmd/api/main.go` | Wires S3 client, attachmentRepo, attachmentSvc, attachmentHandler. Mounts `/tasks/:id/attachments` sub-group. Replaces stub cron tick with real `AttachmentCleanupJob.Run`. |
| `go.mod` / `go.sum` | Adds `aws-sdk-go-v2 v1.41.7` + dependencies. Go 1.23 → 1.24. |

#### API routes added (per CON-002 §4)

| Method | Path | Status |
|:-------|:-----|:-------|
| `POST` | `/api/v1/tasks/:id/attachments` | 201 — pre-register, returns upload URL |
| `POST` | `/api/v1/tasks/:id/attachments/:aid/confirm` | 204 — confirm upload complete |
| `GET` | `/api/v1/tasks/:id/attachments` | 200 — list COMPLETE attachments |
| `GET` | `/api/v1/tasks/:id/attachments/:aid/url` | 200 — get fresh download URL |
| `DELETE` | `/api/v1/tasks/:id/attachments/:aid` | 204 — delete attachment |

---

### 2.2. SPR-004-BE — Gamification Engine

Full server-side gamification: streak + grace day logic, tree health score, badge award engine (all 14 badges), nightly decay, and the gamification API endpoints.

#### New files

| File | Description |
|:-----|:------------|
| `db/migrations/0009_create_badges.sql` | `badges` catalog table (BLU-002 §3.8). |
| `db/migrations/0010_create_user_badges.sql` | `user_badges` junction with `UNIQUE(user_id, badge_id)` for idempotent award. |
| `db/migrations/0011_create_device_tokens.sql` | `device_tokens` schema (V2 FCM pre-provision; no MVP API endpoints). |
| `db/migrations/0012_seed_badges.sql` | All 14 badges per BLU-002-SD §2.1 (exact content from reference doc). |
| `internal/repositories/badge_repository.go` | `BadgeRepository` interface: `TryAward` (ON CONFLICT DO NOTHING → returns `bool` — was it newly awarded?), `GetAllBadges`, `GetUserBadges`, `CountTasksCompletedToday`. |
| `internal/handlers/gamification_handler.go` | `GET /gamification/state` + `GET /gamification/badges`. |

#### Modified files

| File | Change |
|:-----|:-------|
| `internal/repositories/auth_repository.go` | Extends `GamificationStateReader` interface with `UpdateGraceUsedAt`, `UpdateNightlyDecay`, `UpdateTreeHealth`. Adds concrete implementations to `GamificationRepository`. |
| `internal/services/gamification_service.go` | Full engine rewrite. See §2.2.1 below. |
| `internal/services/gamification_service_test.go` | Full test rewrite. All 9 required SPR-004-BE tests. |
| `internal/services/task_service_test.go` | Updated mock stubs to satisfy expanded `GamificationService` interface. |
| `cmd/api/main.go` | Wires `BadgeRepository`, updated `NewGamificationService(stateRepo, badgeRepo)`, `GamificationHandler`. Mounts `/gamification` group. |

#### 2.2.1 Gamification Service Architecture

```
GamificationService.OnTaskCompleted(ctx, userID)
  ├── GetByUserID — load prev state
  ├── Snapshot prevStreak, prevHealth, prevHasCompletedFirst   ← AUD-002 §Finding #3 fix
  ├── daysSinceActive switch:
  │     0  → idempotent (already active today)
  │     1  → increment streak
  │     2+ → applyMissedDay()
  │           ├── WELCOME guard (!hasCompletedFirstTask → no penalty)
  │           ├── graceAvailable? (nil or > 7 days ago) → preserve streak, graceActive=true
  │           └── no grace → streak = 1
  ├── UpdateOnComplete (DB: streak, last_active_date, has_completed_first=true, tree_health LEAST(+5,100))
  ├── CountTasksCompletedToday — for OVERACHIEVER
  └── evaluateInstantBadges() — 9 candidates via TryAward (idempotent)

GamificationService.GetState(ctx, userID)
  └── Returns streak, tree_health, tree_state, sprite_state, grace_active, total_badges_earned

GamificationService.GetBadges(ctx, userID)
  └── All 14 catalog badges with earned=true/false and earned_at

GamificationService.ApplyNightlyDecay(ctx, userID)
  ├── WELCOME guard
  ├── grace available → UpdateGraceUsedAt (streak preserved, no health penalty)
  └── no grace → UpdateNightlyDecay (streak=0, health -10)

GamificationService.ApplyOverduePenalty(ctx, userID, overdueCount)
  ├── WELCOME guard
  └── UpdateTreeHealth (health - overdueCount×3, clamped to [0,100])
```

#### Computed fields (not stored, per BLU-002 §3.7 note)

| Field | THRIVING | HEALTHY | STRUGGLING | WITHERING |
|:------|:---------|:--------|:-----------|:----------|
| `tree_state` (health ≥) | 75 | 50 | 25 | 0 |

| `sprite_state` | Condition |
|:--------------|:----------|
| `WELCOME` | `has_completed_first_task = false` |
| `HAPPY` | streak ≥ 1 AND health ≥ 60 |
| `NEUTRAL` | streak ≥ 1 AND health ≥ 30 |
| `SAD` | otherwise |

#### Instant badges (on task completion)

| Badge ID | Condition (evaluated against pre-mutation snapshot) |
|:---------|:----------------------------------------------------|
| `FIRST_NIBBLE` | `!prevHasCompletedFirstTask` |
| `STREAK_7/14/30/100/365` | `newStreak >= N && prevStreak < N` |
| `OVERACHIEVER` | `taskCountToday >= 10` |
| `TREE_HEALTHY` | `newHealth >= 50 && prevHealth < 50` |
| `TREE_THRIVING` | `newHealth >= 75 && prevHealth < 75` |

> [!IMPORTANT]
> Volume×Streak badges (`CONSISTENT_WEEK`, `CONSISTENT_MONTH`, `PRODUCTIVE_WEEK`, `PRODUCTIVE_MONTH`, `TREE_SUSTAINED`) are **not** evaluated on task completion. They require a nightly cron that queries N-day task count windows per user. This is **SPR-005-BE scope**. The nightly `ApplyNightlyDecay` and `ApplyOverduePenalty` methods are implemented but the **user iteration loop** (who to call them for) is also SPR-005-BE.

#### API routes added (per CON-002 §5)

| Method | Path | Status |
|:-------|:-----|:-------|
| `GET` | `/api/v1/gamification/state` | 200 — full state with computed fields |
| `GET` | `/api/v1/gamification/badges` | 200 — all 14 badges with earned status |

---

## 3. Test Coverage

### SPR-003-BE — Attachment Service Tests

| Test | Result |
|:-----|:-------|
| Pre-register returns presigned URL + S3 called | ✅ |
| Pre-register blocks at 10-attachment limit | ✅ |
| Pre-register rejects disallowed MIME type | ✅ |
| Pre-register rejects file > 200 MiB | ✅ |
| Confirm sets COMPLETE + confirmed_at | ✅ |
| Confirm on already-COMPLETE returns 422 | ✅ |
| Delete calls S3 first, then removes DB row | ✅ |
| List returns only COMPLETE attachments | ✅ |
| S3 presign failure prevents DB row creation | ✅ |

### SPR-004-BE — Gamification Service Tests

| Test | Result |
|:-----|:-------|
| Day missed, grace available → streak preserved, grace_active=true | ✅ |
| Day missed, grace used 3 days ago (in-window) → streak resets to 1 | ✅ |
| Day missed, grace used 8 days ago (out-of-window) → grace refreshed | ✅ |
| First completion → FIRST_NIBBLE awarded | ✅ |
| Streak reaches 7 → STREAK_7 awarded; not awarded twice (idempotent) | ✅ |
| 10 tasks today → OVERACHIEVER awarded | ✅ |
| WELCOME state: ApplyNightlyDecay is a no-op | ✅ |
| Overdue penalty: -3 × overdueCount applied to tree health | ✅ |
| WELCOME guard: overdue penalty not applied in WELCOME state | ✅ |

---

## 4. Architect Audit Checklist

> Items the Architect must verify during AUD-003-BE and AUD-004-BE.

### SPR-003-BE Attachment Audit Points

- [ ] **`0008_create_task_attachments.sql`** — matches BLU-002 §3.6 column spec and index strategy exactly
- [ ] **S3 key format** — `{user_id}/{task_id}/{attachment_id}.{ext}` — verify no path traversal risk (all components are UUIDs or Go's `filepath.Ext()`)
- [ ] **Presign before insert** — confirm code order in `PreRegister`: S3 presign → DB insert (no orphan row on S3 failure)
- [ ] **S3 before DB delete** — confirm code order in `Delete`: S3 DeleteObject → DB DELETE (S3 orphan on DB failure is acceptable, no ghost records)
- [ ] **Content-Type lock** — presigned PUT URL sets `ContentType` param so client cannot override MIME after pre-registration
- [ ] **MIME allowlist** — 14 types in `allowedMIMETypes` map; review if business needs match
- [ ] **Max file size** — 200 MiB cap (client-declared size only; no server-side S3 head check — acceptable per CON-002 §4)
- [ ] **Cleanup cron** — `AttachmentCleanupJob` runs at `00:05 UTC` nightly. Confirm this is acceptable window (orphan PENDING rows cleaned within ~25 hours worst-case)
- [ ] **`go.mod` Go 1.24 upgrade** — `aws-sdk-go-v2/config` requires Go ≥ 1.24. Verify Fly.io Dockerfile builder matches

### SPR-004-BE Gamification Audit Points

- [ ] **`seed_badges.sql`** — `SELECT COUNT(*) FROM badges` must equal 14 in staging after deploy
- [ ] **Snapshot ordering** — `prevStreak` / `prevHealth` / `prevHasCompletedFirst` captured BEFORE `UpdateOnComplete` call (AUD-002 §Finding #3 fix was the original source of this requirement)
- [ ] **Grace day window** — 7-day rolling window: `grace_used_at < today - 7 days` means grace refreshes on day 8. Confirm this matches PRJ-001 §5.5 intent
- [ ] **Idempotency** — `TryAward` uses `ON CONFLICT (user_id, badge_id) DO NOTHING`; returns `bool` — only badge actually inserted goes in delta response
- [ ] **`badges_awarded` is `[]` not `null`** — `evaluateInstantBadges` always returns non-nil slice; confirm JSON serializes to `[]` for empty case
- [ ] **Volume×Streak badges deferred** — `CONSISTENT_*`, `PRODUCTIVE_*`, `TREE_SUSTAINED` not awarded on completion. Confirm SPR-005-BE scope alignment
- [ ] **Nightly decay user iteration** — `ApplyNightlyDecay` and `ApplyOverduePenalty` exist but caller loop is SPR-005-BE. Confirm scope boundary is acceptable
- [ ] **`sprite_state` thresholds** — HAPPY ≥ 60, NEUTRAL ≥ 30 — confirm these match the Flutter companion design (or flag for EVO- if change needed)
- [ ] **`UpdateOnComplete` sets `has_completed_first_task = TRUE`** — always, not conditionally. Verify this is correct for re-completion of tasks (it is: idempotent SET TRUE)

---

## 5. Environment Requirements for Staging

### SPR-003-BE (new secrets required before attachment smoke test)

```bash
# Fly.io secrets — must be set BEFORE deploying the feature branch
fly secrets set AWS_ACCESS_KEY_ID=<key>
fly secrets set AWS_SECRET_ACCESS_KEY=<secret>
fly secrets set AWS_S3_BUCKET=<bucket-name>
fly secrets set AWS_REGION=us-east-1  # or target region
```

> [!CAUTION]
> The app will **fatal on startup** if these four secrets are absent, because `config.go` uses `requireEnv()` for all AWS variables. Do not deploy `feature/B-015-B-045-attachments` to staging without provisioning these secrets first.

### SPR-004-BE (no new environment requirements)

All migrations run via `goose up` on `fly deploy release_command`. No new env vars needed. The four new migration files (0009–0012) are embedded in the binary and will run automatically.

---

## 6. Known Scope Deductions (not bugs — intentional deferrals)

| Item | Status | Rationale |
|:-----|:-------|:----------|
| Volume×Streak badge evaluation | SPR-005-BE | Requires nightly N-day window query across all users |
| `TREE_SUSTAINED` badge | SPR-005-BE | Requires 7-day sustained thriving check in nightly cron |
| Nightly user iteration loop | SPR-005-BE | `ApplyNightlyDecay` + `ApplyOverduePenalty` are implemented but the cron only calls them for individual users when called explicitly — the "for each user" loop is SPR-005 |
| SPR-003 · S3 server-side size validation | Future / EVO | Client declares size; server trusts it. Presigned PUT URL has no size constraint. Could add S3 bucket policy or Lambda trigger if needed |
| `GET /gamification/state` · `grace_active` precision | Minor | Reports whether grace was consumed in last 7 days — does NOT distinguish "grace consumed for missed day" from "grace triggered today". Flutter only needs `true/false`; if richer state is needed, file EVO- |

---

## 7. Branch Push Status

```
feature/B-015-B-045-attachments  → AWAITING PUSH (see §8)
feature/B-031-B-054-gamification → AWAITING PUSH (see §8)
develop                           → PUSHED (39e4044)
```

---

## 8. Architect Next Steps

1. **Pull both branches** — verify `go build ./...` and `go test ./...` pass locally
2. **Run audit checklists** (§4 above) — file `AUD-003-BE.md` and `AUD-004-BE.md` in `CODEX/05_PROJECT/`  
3. **Provision S3 secrets** on Fly.io staging before ordering SPR-003-BE integration smoke test
4. **Merge decision** — if both branches pass audit, merge sequentially: SPR-003-BE first, then SPR-004-BE (order does not matter technically as they share no changed files except `cmd/api/main.go`)
5. **Plan SPR-005-BE** — nightly user iteration loop, volume×streak badges, RRULE expansion cron
6. **EVO- consideration** — `sprite_state` thresholds (HAPPY/NEUTRAL/SAD health cutoffs) should be validated against Flutter UI designer before SPR-004-MB begins
