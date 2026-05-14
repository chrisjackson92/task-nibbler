---
id: BLU-002-SD
title: "Seed Data Reference — Task Nibbles"
type: reference
status: APPROVED
owner: architect
agents: [coder]
tags: [architecture, database, schema, seed-data]
related: [BLU-002, PRJ-001]
created: 2026-05-14
updated: 2026-05-14
version: 1.0.0
---

> **BLUF:** All lookup values, system data, and seed records required before the Task Nibbles application can function. The Backend Developer Agent runs this seed data as part of migration `0012_seed_badges.sql`. This file is the authoritative source — the database must match exactly.

# Seed Data Reference — Task Nibbles

---

## 1. Seeding Order

Seed data must be inserted in this order to satisfy foreign key constraints:

```
1. Enum types      → created by migrations 0001 (no rows, just types)
2. badges table    → migration 0012_seed_badges.sql
3. (all other tables start empty — populated by user registration and activity)
```

---

## 2. `badges` Table Seed Data

The `badges` table is **read-only at runtime**. All 14 badges are seeded at initial deploy. The badge `id` field is the system identifier used by the badge award engine — **never change existing IDs**.

### 2.1 Streak Milestone Badges

```sql
-- +goose Up
-- migration: 0012_seed_badges.sql

INSERT INTO badges (id, name, description, emoji, trigger_type) VALUES

-- ── Streak Milestones ───────────────────────────────────────────────────────
('FIRST_NIBBLE',
 'First Nibble',
 'You completed your very first task. Every journey starts with a single nibble!',
 '🌱',
 'FIRST_TASK'),

('STREAK_7',
 'Week Warrior',
 'You maintained a 7-day streak. Your tree is starting to grow!',
 '🔥',
 'STREAK_MILESTONE'),

('STREAK_14',
 'Fortnight Fighter',
 'Two weeks of consistency — your companion is cheering you on!',
 '⚡',
 'STREAK_MILESTONE'),

('STREAK_30',
 'Monthly Maven',
 'A full month of showing up. You are unstoppable.',
 '🏆',
 'STREAK_MILESTONE'),

('STREAK_100',
 'Century Club',
 '100 days of consistency. Your tree is magnificent.',
 '💯',
 'STREAK_MILESTONE'),

('STREAK_365',
 'Unstoppable',
 'One full year of daily tasking. Legendary.',
 '🌟',
 'STREAK_MILESTONE'),

-- ── Task Volume × Streak ────────────────────────────────────────────────────
('CONSISTENT_WEEK',
 'Consistent Week',
 'You completed 3 or more tasks every day for a full week. True consistency!',
 '🎯',
 'VOLUME_STREAK'),

('CONSISTENT_MONTH',
 'Consistent Month',
 'You completed 3 or more tasks every day for a full month. Extraordinary!',
 '🚀',
 'VOLUME_STREAK'),

('PRODUCTIVE_WEEK',
 'Productive Week',
 'You completed 5 or more tasks every day for a full week. Powerhouse!',
 '🎯',
 'VOLUME_STREAK'),

('PRODUCTIVE_MONTH',
 'Productive Month',
 'You completed 5 or more tasks every day for a full month. Elite performer!',
 '🚀',
 'VOLUME_STREAK'),

('OVERACHIEVER',
 'Daily Overachiever',
 'You completed 10 or more tasks in a single day. Incredible!',
 '⚡',
 'DAILY_VOLUME'),

-- ── Tree Health ─────────────────────────────────────────────────────────────
('TREE_HEALTHY',
 'Sprout',
 'Your tree reached a healthy state for the first time. Keep it growing!',
 '🌿',
 'TREE_HEALTH'),

('TREE_THRIVING',
 'In Bloom',
 'Your tree is thriving! Consistent effort has made it flourish.',
 '🌸',
 'TREE_HEALTH'),

('TREE_SUSTAINED',
 'Full Canopy',
 'Your tree has been thriving for 7 consecutive days. Magnificent!',
 '🌳',
 'TREE_HEALTH');

-- +goose Down
DELETE FROM badges WHERE id IN (
  'FIRST_NIBBLE', 'STREAK_7', 'STREAK_14', 'STREAK_30', 'STREAK_100', 'STREAK_365',
  'CONSISTENT_WEEK', 'CONSISTENT_MONTH', 'PRODUCTIVE_WEEK', 'PRODUCTIVE_MONTH',
  'OVERACHIEVER', 'TREE_HEALTHY', 'TREE_THRIVING', 'TREE_SUSTAINED'
);
```

---

## 3. Badge Award Trigger Reference

The badge award engine (Go service) uses this table to determine when to award each badge. Evaluated on **task completion** and **nightly cron**.

| Badge ID | Trigger Condition | Evaluated |
|:---------|:------------------|:----------|
| `FIRST_NIBBLE` | `has_completed_first_task` transitions from FALSE → TRUE | On task complete |
| `STREAK_7` | `streak_count` reaches 7 | On task complete |
| `STREAK_14` | `streak_count` reaches 14 | On task complete |
| `STREAK_30` | `streak_count` reaches 30 | On task complete |
| `STREAK_100` | `streak_count` reaches 100 | On task complete |
| `STREAK_365` | `streak_count` reaches 365 | On task complete |
| `CONSISTENT_WEEK` | For 7 consecutive days: COUNT(completed tasks) ≥ 3 each day | Nightly cron |
| `CONSISTENT_MONTH` | For 30 consecutive days: COUNT(completed tasks) ≥ 3 each day | Nightly cron |
| `PRODUCTIVE_WEEK` | For 7 consecutive days: COUNT(completed tasks) ≥ 5 each day | Nightly cron |
| `PRODUCTIVE_MONTH` | For 30 consecutive days: COUNT(completed tasks) ≥ 5 each day | Nightly cron |
| `OVERACHIEVER` | COUNT(tasks completed today) ≥ 10 | On task complete |
| `TREE_HEALTHY` | `tree_health_score` first crosses ≥ 50 | On task complete |
| `TREE_THRIVING` | `tree_health_score` first crosses ≥ 75 | On task complete |
| `TREE_SUSTAINED` | `tree_health_score` ≥ 75 for 7 consecutive calendar days | Nightly cron |

**Idempotency rule:** Before inserting into `user_badges`, always check `SELECT 1 FROM user_badges WHERE user_id = $1 AND badge_id = $2`. If exists, skip — never error.

---

## 4. Default Gamification State (Application Code)

When a new user registers, the registration handler must create a `gamification_state` row immediately:

```go
// internal/services/auth_service.go — called inside the register transaction
func (s *AuthService) createDefaultGamificationState(ctx context.Context, userID uuid.UUID) error {
    return s.gamificationRepo.Create(ctx, db.CreateGamificationStateParams{
        UserID:                 userID,
        StreakCount:            0,
        HasCompletedFirstTask:  false,
        TreeHealthScore:        50, // starts in HEALTHY territory, neutral
    })
}
```

**Default values at registration:**

| Field | Default | Rationale |
|:------|:--------|:----------|
| `streak_count` | `0` | No streak yet |
| `last_active_date` | `NULL` | No activity yet |
| `grace_used_at` | `NULL` | No grace consumed |
| `has_completed_first_task` | `FALSE` | WELCOME state active |
| `tree_health_score` | `50` | Starts in HEALTHY zone — neutral, not punishing |

---

## 5. Enum Value Reference

These are the authoritative enum values. The application layer must use these exact strings.

### `task_priority`
| Value | Display Label | Sort Order |
|:------|:-------------|:-----------|
| `LOW` | Low | 4 |
| `MEDIUM` | Medium | 3 |
| `HIGH` | High | 2 |
| `CRITICAL` | Critical | 1 |

### `task_type`
| Value | Display Label |
|:------|:-------------|
| `ONE_TIME` | One-time |
| `RECURRING` | Recurring |

### `task_status` (stored values)
| Value | Display Label | Score Impact |
|:------|:-------------|:------------|
| `PENDING` | Pending | None until overdue |
| `COMPLETED` | Completed | +5 tree health |
| `CANCELLED` | Cancelled | Zero |
| *(OVERDUE — calculated)* | Overdue | -3 tree health/day (nightly) |

### `attachment_status`
| Value | Meaning |
|:------|:--------|
| `PENDING` | S3 upload in progress — not yet confirmed |
| `COMPLETE` | Upload confirmed — attachment is live |

### `device_platform`
| Value | Meaning |
|:------|:--------|
| `ios` | Apple iOS device — FCM token (APNs via FCM) |
| `android` | Android device — FCM token |

### `badge_trigger_type`
| Value | Meaning |
|:------|:--------|
| `FIRST_TASK` | Triggered on first task completion |
| `STREAK_MILESTONE` | Triggered when streak_count hits a threshold |
| `VOLUME_STREAK` | Triggered by N consecutive days with M+ completions |
| `DAILY_VOLUME` | Triggered by N+ completions in a single day |
| `TREE_HEALTH` | Triggered by tree_health_score crossing a threshold |

---

> *"Seed data is infrastructure. Treat it with the same rigour as schema migrations."*
