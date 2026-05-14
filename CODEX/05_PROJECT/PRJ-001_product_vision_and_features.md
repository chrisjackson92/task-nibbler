---
id: PRJ-001
title: "Task Nibbles — Product Vision & Feature Roadmap"
type: planning
status: APPROVED
owner: human
agents: [all]
tags: [project-management, roadmap, product-vision]
related: [BCK-001, BLU-002, BLU-003, BLU-004, GOV-008]
created: 2026-05-14
updated: 2026-05-14
version: 1.0.0
---

> **BLUF:** Task Nibbles is a gamified mobile task manager for Android and iOS. Users track tasks, attach media, build consistency streaks, and watch an animated companion grow or wither based on their habits. This document is the source of truth for all sprint planning.

# PRJ-001 — Task Nibbles: Product Vision & Feature Roadmap

---

## 1. Product Vision

Task Nibbles is a **mobile task manager that turns daily habits into a game** — rewarding consistent users with a growing animated companion and punishing neglect with a sad, withering tree.

### Core Value Proposition

> **Make doing your tasks feel like feeding a pet you love — miss too many, and it suffers.**

### Key Differentiator

Most task managers reward completion in isolation. Task Nibbles rewards *consistency over time* — the gamification engine tracks streaks and health scores that persist across sessions, creating emotional investment in the habit of task completion.

### Inspirations

- **Habitica** — gamification of habits/tasks, RPG-style rewards
- **Duolingo** — streak mechanic creating genuine FOMO for consistency
- **Forest** — tree growth as a visual consequence of behavior
- **Things 3** — clean, opinionated task UX without clutter

---

## 2. Target Users

| Segment | Description | Primary Pain Point |
|:--------|:------------|:-------------------|
| **Habit Builders** | Adults 18–35 trying to build consistent daily routines | Todo apps have no emotional hook — tasks pile up and get ignored |
| **Students** | College/university students managing coursework + personal tasks | Assignment tracking is dull; no motivation to stay on top of it |
| **Busy Professionals** | People with high task loads who need quick capture + scheduling | Need rich task detail (attachments, addresses, times) without enterprise bloat |
| **Visual Thinkers** | Users who are motivated by visible progress representations | Plain lists don't communicate progress; they need to *see* their consistency |

---

## 3. Core Features (MVP)

| # | Feature | Description | Priority |
|:--|:--------|:------------|:---------|
| 1 | **User Authentication** | Register, login, JWT refresh, logout. Accounts are required — all data is user-scoped. | P0 |
| 2 | **Task CRUD** | Create, read, update, delete tasks. Full field set: title, description, address, rank/weight/priority, start time (optional), end time (optional), task type (one-time or recurring). | P0 |
| 3 | **Task Completion** | Mark a task complete. Triggers gamification engine server-side (streak update + tree health recalculation). | P0 |
| 4 | **Media Attachments** | Attach photos and videos (max 200 MB per file) to any task. Stored in AWS S3 via presigned URL upload. View/delete attachments in task detail. | P1 |
| 5 | **Recurring Tasks** | Define tasks that repeat on a schedule (daily, weekly, custom). Server-side cron expands RRULE into concrete task instances nightly. | P1 |
| 6 | **Gamification — Sprite Companion** | An animated character (Rive) that reacts to consistency: cheering/happy when on a streak, sad/drooping when streak breaks. | P2 |
| 7 | **Gamification — Tree** | An animated tree (Rive) tied to `tree_health_score` (0–100): lush and growing at high health, withering and dying at low health. Health increases on task completion, decays daily on missed tasks. | P2 |
| 8 | **Offline Read Cache** | App shows last-known task list when offline (Hive local cache). Write actions (create, complete, delete) are disabled with a friendly banner. Full offline-first sync is a V2 feature. | P2 |

**Priority Legend:**
- **P0** — Blocking; nothing works without this
- **P1** — Core value; MVP is incomplete without this
- **P2** — Enhances experience; defer only if timeline is critical
- **P3** — Nice to have; post-MVP

---

## 4. User Flows (Happy Path)

### 4.1 Onboarding — New User

```
1. Open Task Nibbles for the first time
2. See welcome screen with app name + companion sprite preview
3. Tap "Get Started" → Registration screen
4. Enter email + password → POST /auth/register
5. Auto-logged in → redirect to Task List (empty state)
6. Empty state shows companion sprite + prompt: "Add your first task!"
```

### 4.2 Core Daily Loop — Creating and Completing a Task

```
1. Tap "+" FAB → Task creation form
2. Fill in: title (required), description, address, priority, start/end time
3. Toggle "Recurring" if the task repeats → choose frequency
4. Optionally attach a photo or video (opens camera/gallery picker)
5. Tap "Save" → POST /tasks
6. Task appears in the list
7. Tap task → Task detail view
8. Tap "Complete" → POST /tasks/:id/complete
9. Server updates streak + tree health
10. Companion sprite animates: cheers if streak maintained
11. Tree visually grows slightly
```

### 4.3 Streak Break — Missing Tasks

```
1. User misses completing tasks for 1+ days
2. Nightly cron runs → tree_health_score decreases, streak resets if applicable
3. User opens app next day
4. Companion sprite looks droopy/sad
5. Tree appears more withered
6. App shows streak summary: "You had a 7-day streak! Start again today."
7. User completes a task → sprite cheers, tree begins recovering
```

### 4.4 Offline Usage

```
1. User loses internet connection
2. App detects offline state (connectivity_plus)
3. Task list loads from Hive local cache (read-only)
4. FAB ("+" create) is disabled; a banner shows: "You're offline — syncing when reconnected"
5. User can browse existing tasks and attachments (if cached)
6. User reconnects → banner disappears, full functionality restored
```

---

## 5. Feature Specifications

### 5.1 Authentication

- Email + password registration; no social login in MVP
- JWT access token (15-minute expiry) in `Authorization: Bearer` header
- Refresh token (30-day expiry) stored server-side in `refresh_tokens` table (hashed); client stores raw token in `flutter_secure_storage`
- Silent refresh: Dio interceptor refreshes access token automatically on 401
- Logout: client deletes local tokens; server marks refresh token row as `revoked_at = now()`
- Refresh token rotation reuse detection: if a revoked token is replayed, all tokens for that user are immediately revoked
- Password reset: `POST /auth/forgot-password` (sends Resend email) + `POST /auth/reset-password` (token in link)
- Account deletion: `DELETE /auth/account` — deletes all user rows + S3 attachments; required by App Store / Play Store
- Password minimum: 8 characters, at least one uppercase, one number
- Rate limiting: 5 requests/minute per IP on all `/auth/*` routes (Gin middleware)

### 5.2 Task Entity — Full Field Set

| Field | Type | Required | Notes |
|:------|:-----|:---------|:------|
| `title` | string | ✅ | Max 200 chars |
| `description` | string | ❌ | Max 2000 chars |
| `address` | string | ❌ | Free-text address; geocoding is post-MVP |
| `priority` | enum | ✅ | `LOW` / `MEDIUM` / `HIGH` / `CRITICAL` |
| `task_type` | enum | ✅ | `ONE_TIME` / `RECURRING` |
| `status` | enum | ✅ | `PENDING` / `COMPLETED` / `CANCELLED` (stored); `OVERDUE` is a **calculated** field — not stored |
| `sort_order` | integer | ✅ | Client-controlled display order; default = creation order |
| `start_at` | timestamp | ❌ | ISO 8601, UTC |
| `end_at` | timestamp | ❌ | ISO 8601, UTC; must be after `start_at`. Tasks with `end_at` in the past and `status = PENDING` are **OVERDUE**. |
| `completed_at` | timestamp | ❌ | Set by `POST /tasks/:id/complete` |
| `cancelled_at` | timestamp | ❌ | Set by `PATCH /tasks/:id` when status → CANCELLED |

**Task Status Rules:**
- `PENDING` → Default state on creation
- `COMPLETED` → Set by `POST /tasks/:id/complete`; triggers gamification event
- `CANCELLED` → User explicitly abandons task; **zero score impact** — no streak penalty, no tree health change
- `OVERDUE` → Calculated at read time: `status = PENDING AND end_at IS NOT NULL AND end_at < now()`. Nightly cron applies **-3 tree health per overdue task** (lighter than the -10 zero-completion-day penalty)

**Task Filtering (GET /tasks query params):**
`?status=pending|completed|cancelled|overdue&priority=low|medium|high|critical&type=one_time|recurring&from=ISO8601&to=ISO8601&search=text&sort=due_date|priority|sort_order|created_at&order=asc|desc`

### 5.3 Media Attachments

- Max file size: **200 MB per file**
- Accepted MIME types: images (`image/jpeg`, `image/png`, `image/heic`) + video (`video/mp4`, `video/quicktime`)
- **Upload flow (Pattern A — Pre-register):**
  1. Client calls `POST /tasks/:id/attachments` with filename + MIME type
  2. Server creates a `task_attachments` row with `status = PENDING` + returns a presigned S3 PUT URL (TTL: 15 min)
  3. Client uploads file **directly to S3** (server never proxies binary data)
  4. Client calls `POST /tasks/:id/attachments/:id/confirm` → server sets `status = COMPLETE`
  5. A nightly cleanup cron deletes PENDING rows older than 1 hour + their S3 objects (handles failed uploads)
- Download: `GET /tasks/:id/attachments/:id/url` → server returns presigned GET URL (TTL: 60 min)
- Thumbnail generation: post-MVP
- Max attachments per task: **10** (MVP limit)

### 5.4 Recurring Tasks

- Stored as `recurring_rules` with an [iCal RRULE](https://datatracker.ietf.org/doc/html/rfc5545) string (e.g., `FREQ=DAILY;BYDAY=MO,TU,WE`)
- RRULE expansion uses the **user's stored timezone** (UTC if unset) to correctly compute "daily 9am" in the user's local time
- Server-side cron (`go-cron`) runs nightly at 00:05 UTC, expands all active recurring rules into concrete task instances for the next 30 days
- If a concrete task instance already exists for a date, it is skipped (idempotent expansion)
- User sees concrete instances in their task list, not the abstract rule
- **Editing a recurring task:** user is prompted at edit time with two options:
  - **"This instance only"** → edits only the selected concrete task row; detaches it from the recurring rule
  - **"This and all future instances"** → updates the recurring rule + deletes/regenerates all future (uncompleted) instances
- Deleting follows the same two-option pattern

### 5.5 Gamification Engine

**Streak:**
- A streak is the number of consecutive days on which the user completed at least one task
- Streak resets to 0 if a full calendar day passes with zero completions **and no grace day is available**
- **Grace day mechanics:** Each user has one grace day banked at a time (`grace_used_at` field). If a day is missed and grace has not been used in the last 7 days, the streak is preserved and `grace_used_at = today`. The streak counter shows a ⚡ indicator while grace is active.
- Streak is stored server-side: `gamification_state.streak_count`, `last_active_date`, `grace_used_at`

**New User State:**
- `has_completed_first_task = false` on account creation
- Gamification widget shows a **WELCOME** state (neutral, encouraging sprite) until first task is completed
- Gamification scoring does **not** penalize users in WELCOME state — zero-completion-day decay only activates after first completion

**Tree Health Score (0–100):**
- New users start at **50**
- `+5` for each task completed (capped at 100)
- `-10` per calendar day with zero completions (floors at 0)
- `-3` per **OVERDUE** task (task with `end_at < now()` and `status = PENDING`) — applied nightly
- `CANCELLED` tasks: **zero impact** — cancellation is not a failure
- Recalculated nightly by the cron job

**Sprite Companion States:**
- `WELCOME` → `has_completed_first_task = false`
- `HAPPY` → streak_count ≥ 1 AND tree_health_score ≥ 60
- `NEUTRAL` → streak_count ≥ 1 AND tree_health_score 30–59
- `SAD` → streak_count = 0 OR tree_health_score < 30

**Tree Animation States:**
- `THRIVING` → tree_health_score ≥ 75
- `HEALTHY` → tree_health_score 50–74
- `STRUGGLING` → tree_health_score 25–49
- `WITHERING` → tree_health_score < 25

**Home Screen Gamification Hero:**
The home / task-list screen features a **collapsible gamification hero section** at the top displaying:
- The Rive sprite companion (animated, reacts to current state)
- A compact tree health bar + tree state label
- Current streak count + grace day indicator (if active)
Tapping the hero expands to the full **Gamification Detail Screen** (full-size tree animation + badge shelf + reward history).

**Badge Catalog (Consistency Rewards):**

*Streak Milestone Badges:*
| Badge | ID | Trigger |
|:------|:---|:--------|
| 🌱 First Nibble | `FIRST_NIBBLE` | Complete first task ever |
| 🔥 Week Warrior | `STREAK_7` | 7-day streak |
| ⚡ Fortnight Fighter | `STREAK_14` | 14-day streak |
| 🏆 Monthly Maven | `STREAK_30` | 30-day streak |
| 💯 Century Club | `STREAK_100` | 100-day streak |
| 🌟 Unstoppable | `STREAK_365` | 365-day streak |

*Task Volume × Streak Badges:*
| Badge | ID | Trigger |
|:------|:---|:--------|
| 🎯 Consistent Week | `CONSISTENT_WEEK` | 7-day streak with ≥3 tasks/day |
| 🚀 Consistent Month | `CONSISTENT_MONTH` | 30-day streak with ≥3 tasks/day |
| 🎯 Productive Week | `PRODUCTIVE_WEEK` | 7-day streak with ≥5 tasks/day |
| 🚀 Productive Month | `PRODUCTIVE_MONTH` | 30-day streak with ≥5 tasks/day |
| ⚡ Daily Overachiever | `OVERACHIEVER` | 10+ tasks completed in a single day |

*Tree Health Badges:*
| Badge | ID | Trigger |
|:------|:---|:--------|
| 🌿 Sprout | `TREE_HEALTHY` | Tree reaches HEALTHY (≥50) for first time |
| 🌸 In Bloom | `TREE_THRIVING` | Tree reaches THRIVING (≥75) for first time |
| 🌳 Full Canopy | `TREE_SUSTAINED` | Tree maintains THRIVING for 7 consecutive days |

Badge awards are evaluated nightly by the cron job and immediately on task completion. Each badge can only be awarded once per user (idempotent check).

---

## 6. Non-Functional Requirements

| Requirement | Target | Notes |
|:------------|:-------|:------|
| API Response Time | < 200ms p95 (excluding S3 presign) | Go on Fly.io — easily achievable |
| Availability | 99.5% uptime | Fly.io SLA; auto-restart on crash |
| Security | JWT auth on all routes; HTTPS enforced; secrets never in code | GOV-008 enforcement |
| Scalability | Supports 1,000 concurrent users on shared-cpu-1x (MVP) | Go goroutines handle easily |
| Accessibility | WCAG 2.1 AA for the Flutter app (semantic labels, contrast ratios) | GOV-003 enforcement |
| Attachment Upload | Support 200 MB files without timeout | Presigned URL (client → S3 direct); no proxy |

---

## 7. Release Roadmap

### MVP — V1: "Core Nibbles" *(Sprints 1–3)*

- [ ] User registration + login + JWT auth + password reset (Resend)
- [ ] Account deletion (App Store compliance)
- [ ] Full task CRUD with all fields (incl. status, sort_order, timezone)
- [ ] Task filtering + sorting (`GET /tasks` with query params)
- [ ] Settings screen (logout, delete account, change password)
- [ ] Task completion → gamification state update (streak, tree health, badge check)
- [ ] Overdue task detection + nightly score penalty
- [ ] Grace day mechanic
- [ ] Media attachment upload/view/delete (S3, Pattern A confirm flow)
- [ ] Offline read cache (Hive)
- [ ] Home screen gamification hero (sprite + tree health bar)

### V2 — "Alive" *(Sprints 4–5)*

- [ ] Full Rive sprite companion animations (WELCOME / HAPPY / NEUTRAL / SAD)
- [ ] Full Rive tree animations (THRIVING / HEALTHY / STRUGGLING / WITHERING)
- [ ] Badge shelf + award toasts
- [ ] Recurring tasks (RRULE + nightly cron + edit scope dialog)
- [ ] Push notifications: FCM — streak reminders, badge awards, overdue alerts

### V3 — "Power Users" *(Post-MVP)*

- [ ] Full offline-first sync with conflict resolution
- [ ] Shared tasks / collaboration
- [ ] Task categories / tags
- [ ] Home screen widget (iOS/Android)
- [ ] Calendar view
- [ ] Leaderboards (opt-in streak comparison)
- [ ] Geocoding for task addresses

---

## 8. Tech Stack Decisions

| Layer | Technology | Blueprint | Decision Date |
|:------|:-----------|:----------|:--------------|
| **Database** | PostgreSQL 16 | BLU-002 | 2026-05-14 |
| **Backend language** | Go 1.22 | BLU-003 | 2026-05-14 |
| **Backend framework** | Gin + sqlc + pgx | BLU-003 | 2026-05-14 |
| **Auth** | JWT (access 15min) + refresh token rotation (30d), server-side revocation | BLU-003 | 2026-05-14 |
| **Email service** | Resend (password reset; 3,000 free emails/month) | BLU-003, GOV-008 | 2026-05-14 |
| **API contract** | OpenAPI 3.1 (generated from Go) | CON-002 | 2026-05-14 |
| **Recurring jobs** | go-cron (in-process) | BLU-003 | 2026-05-14 |
| **File storage** | AWS S3 (presigned URL Pattern A: pre-register + confirm) | BLU-002 | 2026-05-14 |
| **Mobile framework** | Flutter (Dart) | BLU-004 | 2026-05-14 |
| **Mobile state** | flutter_bloc (BLoC/Cubit pattern) | BLU-004 | 2026-05-14 |
| **Mobile animations** | Rive (sprite companion + tree; home screen hero) | BLU-004 | 2026-05-14 |
| **Mobile cache** | Hive (offline read cache) | BLU-004 | 2026-05-14 |
| **Push notifications** | Firebase Cloud Messaging (FCM) — device_tokens table pre-provisioned in DB | BLU-004 | 2026-05-14 |
| **Deployment** | Fly.io (Go binary in Docker) | GOV-008, RUN-001, RUN-002 | 2026-05-14 |

---

## 9. Open Decisions

| # | Question | Impact | Status |
|:--|:---------|:-------|:-------|
| 1 | App Store names / bundle IDs (`com.tasknibbles.app`)? | Required before App Store submission | OPEN |
| 2 | Rive animation assets — self-created or commissioned? | **Blocking SPR-004-MB** — must be resolved before gamification sprint starts | OPEN |
| 3 | User timezone: auto-detect from device or manual selection in settings? | Recurring task RRULE expansion; affects nightly cron | OPEN |

---

> *"A product vision that can't be broken into tasks isn't a vision — it's a wish."*
