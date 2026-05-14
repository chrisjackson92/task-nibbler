---
id: SPR-004-BE
title: "Sprint 4 — Gamification Backend"
type: sprint
status: BLOCKED
assignee: coder
agent_boot: AGT-002-BE_Backend_Developer_Agent.md
sprint_number: 4
track: backend
estimated_days: 4
blocked_by: SPR-002-BE (gamification_state table must exist)
related: [BLU-002, BLU-003, BLU-002-SD, CON-002, PRJ-001]
created: 2026-05-14
updated: 2026-05-14
---

> **BLUF:** Implement the complete server-side gamification engine: streak + grace day logic, tree health score (with overdue penalties), badge award engine (all 14 badges), full nightly cron suite, and the gamification API endpoints. By the end, the entire scoring system is automated and the Flutter app can display live gamification state.

# Sprint 4-BE — Gamification Backend

---

## Pre-Conditions

- [ ] `SPR-002-BE` Architect audit PASSED (gamification_state table exists)
- [ ] Read `PRJ-001` §5.5 (Gamification Engine — full spec) in full
- [ ] Read `BLU-002_Database_Schema.md` §§3.7–3.9 (gamification_state, badges, user_badges) in full
- [ ] Read `BLU-002-SD_Seed_Data_Reference.md` §2–3 (badge catalog + trigger reference) in full
- [ ] Read `BLU-003_Backend_Architecture.md` §9 (Nightly Cron Jobs) in full
- [ ] Read `CON-002_API_Contract.md` §5 (Gamification routes) in full

---

## Exit Criteria

- [ ] `GET /gamification/state` returns full state block with calculated `tree_state` + `sprite_state`
- [ ] `GET /gamification/badges` returns all 14 badges (earned + locked)
- [ ] Task completion awards `FIRST_NIBBLE` badge on first ever completion
- [ ] Task completion awards `STREAK_7` at streak = 7 (and all other STREAK_* milestones)
- [ ] Grace day: missed day within 7 days of last grace → streak preserved
- [ ] Zero-completion day: streak resets + -10 tree health (run nightly decay manually to verify)
- [ ] OVERDUE penalty: -3 per overdue task applied nightly
- [ ] All 12 badge triggers confirmed working (manual test + unit tests)
- [ ] WELCOME state: user with `has_completed_first_task=false` returns `sprite_state: "WELCOME"` and receives no decay penalties
- [ ] Nightly cron job runs without panic in staging — check `fly logs`
- [ ] `0012_seed_badges.sql` migration inserts all 14 badges correctly
- [ ] `go test ./...` passes, ≥ 70% coverage on gamification service + badge engine

---

## Task List

| BCK ID | Task | Notes |
|:-------|:-----|:------|
| B-021 | Gamification DB schema (full: gamification_state table on staging) | Already from SPR-002-BE; verify all fields including grace_used_at, has_completed_first_task |
| B-031 | Gamification DB schema (badges + user_badges tables + migrations) | 0009, 0010, 0012 |
| B-032 | device_tokens table migration | 0011_create_device_tokens.sql |
| B-046 | gamification_state: grace_used_at, has_completed_first_task fields | Confirm these columns exist (add migration if not) |
| B-047 | badges catalog table + migration | 0009_create_badges.sql |
| B-048 | user_badges junction table + sqlc queries | 0010_create_user_badges.sql |
| B-049 | device_tokens table | 0011 (for V2 FCM; no API endpoints in MVP) |
| B-050 | Grace day logic in streak calculation | See PRJ-001 §5.5 |
| B-051 | WELCOME state: no penalties until has_completed_first_task=true | Guard in all decay logic |
| B-052 | Overdue penalty job: -3 per overdue task nightly | Part of nightly_cron.go |
| B-053 | Badge award engine: all 14 badges, idempotent | Uses `ON CONFLICT DO NOTHING` on user_badges |
| B-054 | GET /gamification/badges | Returns all 14 with earned status |

---

## Technical Notes

### Badge Award Engine Architecture
```go
// internal/services/badge_service.go
type BadgeService struct {
    badgeRepo GamificationRepository
}

func (s *BadgeService) EvaluateOnCompletion(ctx context.Context, userID uuid.UUID, state *GamificationState, taskCountToday int) ([]Badge, error) {
    var awarded []Badge
    candidates := []struct {
        id        string
        condition bool
    }{
        {"FIRST_NIBBLE", !state.HasCompletedFirstTask},
        {"STREAK_7",     state.StreakCount == 7},
        {"STREAK_14",    state.StreakCount == 14},
        {"STREAK_30",    state.StreakCount == 30},
        {"STREAK_100",   state.StreakCount == 100},
        {"STREAK_365",   state.StreakCount == 365},
        {"OVERACHIEVER", taskCountToday >= 10},
        {"TREE_HEALTHY", state.TreeHealthScore >= 50 && state.PrevTreeHealth < 50},
        {"TREE_THRIVING",state.TreeHealthScore >= 75 && state.PrevTreeHealth < 75},
    }
    for _, c := range candidates {
        if c.condition {
            awarded = append(awarded, s.tryAward(ctx, userID, c.id)...)
        }
    }
    return awarded, nil
}

// tryAward: INSERT INTO user_badges ON CONFLICT (user_id, badge_id) DO NOTHING
// Returns badge only if it was actually inserted (not a duplicate)
```

### Grace Day Logic
```go
// internal/services/gamification_service.go
func (s *GamificationService) applyDayMissed(ctx context.Context, state *GamificationState, today time.Time) {
    if !state.HasCompletedFirstTask {
        return // WELCOME state — no penalty
    }
    graceAvailable := state.GraceUsedAt == nil ||
                      state.GraceUsedAt.Before(today.AddDate(0, 0, -7))
    if graceAvailable {
        state.GraceUsedAt = &today // consume grace, preserve streak
    } else {
        state.StreakCount = 0     // reset streak
        state.TreeHealthScore = max(0, state.TreeHealthScore-10)
    }
}
```

### `gamification_delta` response from CON-002
```go
type GamificationDelta struct {
    StreakCount      int     `json:"streak_count"`
    TreeHealthScore  int     `json:"tree_health_score"`
    TreeHealthDelta  int     `json:"tree_health_delta"`
    GraceActive      bool    `json:"grace_active"`
    BadgesAwarded    []Badge `json:"badges_awarded"` // empty slice, not null
}
```

### Seed Migration
```
0012_seed_badges.sql
```
Copy content exactly from `BLU-002-SD_Seed_Data_Reference.md` §2.1.

---

## Testing Requirements

| Test | Type | Required |
|:-----|:-----|:---------|
| `GamificationService: day missed with grace available → streak preserved` | Unit | ✅ |
| `GamificationService: day missed, grace used 3 days ago → streak reset` | Unit | ✅ |
| `GamificationService: day missed, grace used yesterday → streak reset (7-day window)` | Unit | ✅ |
| `BadgeEngine: first completion → FIRST_NIBBLE awarded` | Unit | ✅ |
| `BadgeEngine: streak reaches 7 → STREAK_7 awarded once only` | Unit | ✅ |
| `BadgeEngine: idempotent → STREAK_7 not awarded twice` | Unit | ✅ |
| `BadgeEngine: 10 tasks in a day → OVERACHIEVER awarded` | Unit | ✅ |
| `WELCOME state: zero-completion day → NO streak reset, NO tree health decay` | Unit | ✅ |
| `NightlyCron: overdue task → -3 applied to owner's tree health` | Unit | ✅ |

---

## Architect Audit Checklist

- [ ] `seed_badges.sql` confirmed: `SELECT COUNT(*) FROM badges` = 14
- [ ] `sprite_state` and `tree_state` are calculated server-side, not stored
- [ ] Grace day field `grace_used_at`: NULL for new users, set only on first grace consumption
- [ ] `has_completed_first_task = TRUE` set immediately on first task completion (in same service call, before badge evaluation)
- [ ] `badges_awarded` in delta response is `[]` (empty array), never `null`
- [ ] Volume×Streak badges (`CONSISTENT_*`, `PRODUCTIVE_*`) evaluated by nightly cron, not on completion
