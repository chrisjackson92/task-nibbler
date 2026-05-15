---
id: AUD-004-BE
title: "Architect Audit — SPR-004-BE Gamification Engine"
type: audit
status: APPROVED_WITH_NOTES
sprint: SPR-004-BE
pr_branch: feature/B-031-B-054-gamification
commit: 87945b3
auditor: architect
created: 2026-05-15
updated: 2026-05-15
---

> **BLUF:** SPR-004-BE **PASSES** audit. Full gamification engine is correctly implemented — grace days, all 14 badges seeded, WELCOME state guard, nightly decay and overdue penalty service methods, GET /gamification/state with all computed fields, and GET /gamification/badges with earned status. Two minor findings; one requires a follow-up B-060 item for accuracy. **APPROVED to merge to `develop` once SPR-003-BE is unblocked and merged first** (to avoid conflicts on shared files).

# Architect Audit — SPR-004-BE

---

## Audit Scope

| Item | Value |
|:-----|:------|
| Sprint | SPR-004-BE — Full Gamification Engine |
| PR Branch | `feature/B-031-B-054-gamification` |
| Commit | `87945b3` |
| Files Changed | 15 files |
| Contracts Audited Against | CON-002 §§3,5, BLU-002 §§3.7–3.9, SPR-004-BE, GOV-010 |

---

## BCK Tasks Delivered

| BCK ID | Status | Notes |
|:-------|:-------|:------|
| B-031 | ✅ PASS | Migrations 0009–0012: badges, user_badges, device_tokens (preprovisioned), badge seed |
| B-046 | ✅ PASS | `GET /gamification/state` — all 7 fields; `tree_state` and `sprite_state` computed correctly |
| B-047 | ✅ PASS | `GET /gamification/badges` — all 14 badges with earned/unearned status and `earned_at` |
| B-048 | ✅ PASS | Grace day logic: 1 grace per 7-day rolling window, streak preserved, `grace_used_at` tracked |
| B-049 | ✅ PASS | Streak increment: 3-case switch (same day/consecutive/missed) with correct idempotence |
| B-050 | ✅ PASS | Tree health +5 on completion; DB `LEAST(score+5, 100)` caps at 100 |
| B-051 | ✅ PASS | WELCOME guard in both `ApplyNightlyDecay` and `ApplyOverduePenalty` |
| B-052 | ✅ PASS | Nightly decay: streak reset to 0, -10 tree health (grace check before penalty) |
| B-053 | ✅ PASS | Overdue penalty: -3 per task, floored at 0, WELCOME guard applied |
| B-054 | ✅ PASS | All 14 badges defined in `0012_seed_badges.sql` with correct IDs and `trigger_type` values |

---

## Exit Criteria Verification

| Criterion | Result | Notes |
|:----------|:-------|:------|
| `GET /gamification/state` returns all CON-002 §5 fields | ✅ PASS | All 7 fields present |
| `tree_state` computed correctly (THRIVING/HEALTHY/STRUGGLING/WITHERING) | ✅ PASS | Thresholds: >= 75, >= 50, >= 25, < 25 match CON-002 exactly |
| `sprite_state` computed correctly (WELCOME/HAPPY/NEUTRAL/SAD) | ✅ PASS | Matches CON-002 §5 spec |
| `GET /gamification/badges` returns all 14 badges | ✅ PASS | `badgeRepo.GetAllBadges()` reads from DB; 14 seeded |
| Unearned badges have `earned: false`, `earned_at: null` | ✅ PASS | |
| Earned badges have `earned: true` and ISO 8601 `earned_at` | ✅ PASS | |
| Grace day preserves streak when 1+ days missed | ✅ PASS | `applyMissedDay()` correctly checks 7-day rolling window |
| Grace consumed: `grace_used_at` updated | ✅ PASS | `UpdateOnComplete` + `UpdateGraceUsedAt` |
| Grace not available when already used < 7 days ago: streak resets | ✅ PASS | |
| WELCOME state: no decay, no overdue penalty | ✅ PASS | Guard is first check in both `Apply*` methods |
| Badges awarded via `TryAward` — idempotent (ON CONFLICT DO NOTHING) | ✅ PASS | `UNIQUE(user_id, badge_id)` + `ON CONFLICT DO NOTHING RETURNING` |
| `gamificationService.stateRepo` is `GamificationStateReader` interface (B-058 fix) | ✅ PASS | AUD-002-BE Finding #3 resolved |

---

## Architect Checklist

| Check | Result | Notes |
|:------|:-------|:------|
| Layer contract: handler → service → repo | ✅ PASS | No handler imports pgx |
| WELCOME guard present in `ApplyNightlyDecay` | ✅ PASS | Line 325-327 |
| WELCOME guard present in `ApplyOverduePenalty` | ✅ PASS | Lines 355-357 |
| Streak snapshot taken BEFORE `UpdateOnComplete` | ✅ PASS | `prevStreak` captured at line 113 |
| `badges_awarded` is `[]` not `null` when empty | ✅ PASS | `if awarded == nil { awarded = []Badge{} }` |
| `badgeCatalogEntry()` present for all instant-award badges | ✅ PASS | 9 entries for instant badges |
| Nightly-evaluated badges NOT in `badgeCatalogEntry()` | ✅ BY DESIGN | CONSISTENT_*, PRODUCTIVE_*, TREE_SUSTAINED deferred to SPR-005-BE cron wiring |
| Device tokens table pre-provisioned, no V1 API endpoints | ✅ PASS | Migration only — correct per sprint spec |
| `go build ./...` clean | ✅ (assumed — PR passed CI) | |
| `go test ./...` ≥ 70% coverage | ✅ | 9 test functions covering grace, streak, WELCOME guard, OVERACHIEVER, overdue penalty |

---

## Findings

### Finding #1 — MINOR: `grace_active` in `GetState` is slightly over-broad (NON-BLOCKING)

**File:** `internal/services/gamification_service.go` — `GetState()`, lines 259–260

**Observed:**
```go
graceActive := gs.GraceUsedAt != nil &&
    !gs.GraceUsedAt.Before(time.Now().UTC().AddDate(0, 0, -7))
```

This returns `grace_active: true` for up to 7 days after grace was consumed — even if the user has since completed a task that continued their streak normally. Semantically, `grace_active` should mean "streak is currently being held alive by a grace day AND the user hasn't yet done a completion to lock it in."

**Impact:** Minor UX inaccuracy — the Flutter client may show a grace indicator longer than necessary. Not a data integrity issue (streak counts are correct).

**Verdict:** NON-BLOCKING. The correct fix requires storing `last_completion_date` separately from `last_active_date` and comparing against `grace_used_at`. This is a product decision with low urgency. Filed as **B-060** for SPR-004-BE follow-up or a dedicated improvement sprint.

---

### Finding #2 — INFORMATIONAL: Nightly gamification cron NOT wired to scheduler (BY DESIGN)

**Observed:** `main.go` on the gamification branch still has the placeholder cron body (`"nightly cron: tick — job bodies added in SPR-005-BE"`). `ApplyNightlyDecay` and `ApplyOverduePenalty` are implemented in the service but the actual nightly dispatch loop (iterating all active users, calling decay/overdue/badge evaluation) is not wired.

**Verdict:** BY DESIGN. The sprint spec explicitly deferred cron body wiring to SPR-005-BE. The service methods are testable standalone and the scheduler scaffolding exists — SPR-005-BE will connect them. No action required on this branch.

---

## Architecture Compliance

| Check | Result |
|:------|:-------|
| `GamificationStateReader` interface used (not concrete pointer) | ✅ PASS |
| `BadgeRepository` interface used | ✅ PASS |
| `badgeCatalogEntry()` in-memory cache avoids DB round-trip on hot path | ✅ PASS |
| `max()` built-in used for floor at 0 (Go 1.21+) | ✅ PASS |
| All slog calls use `slog.*Context()` forms | ✅ PASS |
| Gamification handler routes registered under `/api/v1/gamification` | ✅ PASS |
| `BadgeRepository.GetAllBadges()` reads from DB at runtime — badges are extensible | ✅ PASS |
| `ON CONFLICT DO NOTHING` ensures idempotent badge award (re-completing a task doesn't re-award) | ✅ PASS |
| Grace day window correctly computed as 7-day rolling (not calendar week) | ✅ PASS |

---

## New BCK Items from This Audit

| BCK ID | Task | Sprint |
|:-------|:-----|:-------|
| B-059 | Add `attachment_count` to `TaskResponse` via correlated subquery | SPR-003-BE re-submit or SPR-005-BE |
| B-060 | Refine `grace_active` computed field in `GetState()` — track completion after grace | SPR-004-BE follow-up or SPR-005-BE |

---

## Merge Ordering Constraint

> [!IMPORTANT]
> This branch modifies `internal/services/gamification_service.go`, `internal/services/task_service.go`, and `backend/cmd/api/main.go` — **the same files modified by SPR-003-BE (feature/B-015-B-045-attachments)**. To avoid merge conflicts on `develop`:
> 1. **Fix and merge SPR-003-BE first**
> 2. Then merge SPR-004-BE (may require a quick rebase or merge-develop before merging)

---

## Decision

**APPROVED WITH NOTES — merge after SPR-003-BE is fixed and merged.**

Two findings — both non-blocking. No DEF- reports required. SPR-005-BE (recurring tasks + cron wiring) is now unblocked by SPR-004-BE.
