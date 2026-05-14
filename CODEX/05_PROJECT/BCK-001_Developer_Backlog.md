---
id: BCK-001
title: "Developer Backlog — Task Nibbles"
type: planning
status: APPROVED
owner: architect
agents: [coder]
tags: [project-management, backlog, developer]
related: [PRJ-001, BLU-002, BLU-003, BLU-004, CON-001, CON-002]
created: 2026-05-14
updated: 2026-05-14
version: 1.0.0
---

> **BLUF:** This is the prioritized developer backlog for Task Nibbles. Items are ordered by dependency and value. The Architect breaks these into sprint tasks via `SPR-NNN` documents. All items trace back to PRJ-001 (Product Vision).

# Developer Backlog — Task Nibbles

---

## Priority Legend

| Priority | Meaning |
|:---------|:--------|
| **P0** | Must have for MVP — blocking other work |
| **P1** | Must have for MVP — core feature |
| **P2** | Should have for MVP — enhances experience |
| **P3** | Nice to have — defer to post-MVP if needed |

---

## Backend Backlog (Go + Gin + sqlc + pgx)

| # | Feature | Priority | PRJ-001 Ref | Sprint | Status |
|:--|:--------|:---------|:------------|:-------|:-------|
| B-001 | Go module init, project structure, Gin router scaffold | P0 | §8 | SPR-001-BE | [ ] |
| B-002 | PostgreSQL connection (pgx pool), Fly Postgres config | P0 | §8 | SPR-001-BE | [ ] |
| B-003 | sqlc setup, initial migration tooling (goose or migrate) | P0 | §8 | SPR-001-BE | [ ] |
| B-004 | Auth endpoints: POST /auth/register, /auth/login, /auth/refresh, /auth/logout | P0 | §5.1 | SPR-001-BE | [ ] |
| B-005 | JWT middleware (access + refresh token validation) | P0 | §5.1 | SPR-001-BE | [ ] |
| B-006 | Global error handling middleware (GOV-004 compliant) | P0 | — | SPR-001-BE | [ ] |
| B-007 | GET /health endpoint (required by fly.toml health check) | P0 | GOV-008 | SPR-001-BE | [ ] |
| B-008 | OpenAPI / Swagger doc generation (swaggo/swag) | P0 | §8 | SPR-001-BE | [ ] |
| B-009 | Structured JSON logging (GOV-006 compliant, slog or zerolog) | P0 | — | SPR-001-BE | [ ] |
| B-010 | Task CRUD: DB schema (tasks table) + sqlc queries | P0 | §5.2 | SPR-002-BE | [ ] |
| B-011 | Task CRUD: GET /tasks, POST /tasks, GET /tasks/:id, PATCH /tasks/:id, DELETE /tasks/:id | P0 | §5.2 | SPR-002-BE | [ ] |
| B-012 | POST /tasks/:id/complete — marks task done, triggers gamification engine | P0 | §5.5 | SPR-002-BE | [ ] |
| B-013 | Recurring rules schema (recurring_rules table, RRULE storage) | P1 | §5.4 | SPR-002-BE | [ ] |
| B-014 | go-cron scheduler bootstrap (in-process, runs nightly at 00:05 UTC) | P1 | §5.4 | SPR-002-BE | [ ] |
| B-015 | AWS S3 client setup (aws-sdk-go-v2), bucket config | P1 | §4 | SPR-003-BE | [ ] |
| B-016 | POST /tasks/:id/attachments — generate presigned S3 upload URL | P1 | §5.3 | SPR-003-BE | [ ] |
| B-017 | GET /tasks/:id/attachments — list attachments for a task | P1 | §5.3 | SPR-003-BE | [ ] |
| B-018 | DELETE /tasks/:id/attachments/:id — delete from S3 + DB | P1 | §5.3 | SPR-003-BE | [ ] |
| B-019 | Attachment CRUD: DB schema (task_attachments table) + sqlc queries | P1 | §5.3 | SPR-003-BE | [ ] |
| B-020 | File validation: MIME type + 200 MB size limit enforcement | P1 | §5.3 | SPR-003-BE | [ ] |
| B-021 | Gamification DB schema (gamification_state, consistency_rewards tables) | P2 | §5.5 | SPR-004-BE | [ ] |
| B-022 | Gamification engine: streak calculation logic | P2 | §5.5 | SPR-004-BE | [ ] |
| B-023 | Gamification engine: tree health score calculation + decay nightly | P2 | §5.5 | SPR-004-BE | [ ] |
| B-024 | GET /gamification/state — return streak + tree health for current user | P2 | §5.5 | SPR-004-BE | [ ] |
| B-025 | GET /gamification/rewards — list earned consistency rewards | P2 | §5.5 | SPR-004-BE | [ ] |
| B-026 | RRULE expansion cron job — concrete task instances for next 30 days | P1 | §5.4 | SPR-005-BE | [ ] |
| B-027 | Idempotent expansion: skip existing instances | P1 | §5.4 | SPR-005-BE | [ ] |
| B-028 | Dockerfile (multi-stage Go to distroless) | P0 | GOV-008 | SPR-006-OPS | [ ] |
| B-029 | fly.toml configuration (health check, secrets map, auto-stop) | P0 | GOV-008 | SPR-006-OPS | [ ] |
| B-030 | Database migration on deploy (release_command in fly.toml) | P0 | RUN-002 | SPR-006-OPS | [ ] |
| B-031 | GitHub Actions CI/CD pipeline (test to staging to prod) | P1 | RUN-002 | SPR-006-OPS | [ ] |
| B-032 | refresh_tokens DB schema + sqlc queries (hash, revoked_at, user_id, rotation reuse detection) | P0 | §5.1 | SPR-001-BE | [ ] |
| B-033 | Auth: POST /auth/forgot-password (Resend email with reset link + token) | P0 | §5.1 | SPR-001-BE | [ ] |
| B-034 | Auth: POST /auth/reset-password (validate token, set new password) | P0 | §5.1 | SPR-001-BE | [ ] |
| B-035 | Auth: DELETE /auth/account (delete all user data + S3 objects, required by App Store) | P0 | §5.1 | SPR-001-BE | [ ] |
| B-036 | Rate limiting middleware: 5 req/min per IP on all /auth/* routes | P0 | §5.1 | SPR-001-BE | [ ] |
| B-037 | Resend Go SDK integration + password reset email template | P0 | §5.1 | SPR-001-BE | [ ] |
| B-038 | Task DB schema additions: status enum, sort_order, cancelled_at, timezone | P0 | §5.2 | SPR-002-BE | [ ] |
| B-039 | GET /tasks filter params: status, priority, type, from, to, search, sort, order | P0 | §5.2 | SPR-002-BE | [ ] |
| B-040 | OVERDUE calculated field: returned in GET /tasks and GET /tasks/:id | P0 | §5.2 | SPR-002-BE | [ ] |
| B-041 | PATCH /tasks/:id sort_order reordering endpoint | P1 | §5.2 | SPR-002-BE | [ ] |
| B-042 | POST /tasks/:id/attachments — Pattern A pre-register (PENDING row + presigned PUT URL) | P1 | §5.3 | SPR-003-BE | [ ] |
| B-043 | POST /tasks/:id/attachments/:id/confirm — set status = COMPLETE after S3 upload | P1 | §5.3 | SPR-003-BE | [ ] |
| B-044 | GET /tasks/:id/attachments/:id/url — presigned GET URL (TTL 60 min) | P1 | §5.3 | SPR-003-BE | [ ] |
| B-045 | Attachment cleanup cron: delete PENDING rows older than 1 hour + their S3 objects | P1 | §5.3 | SPR-003-BE | [ ] |
| B-046 | Gamification DB schema additions: grace_used_at, has_completed_first_task | P2 | §5.5 | SPR-004-BE | [ ] |
| B-047 | Badge catalog DB schema (badges table: id, name, description, trigger_type) | P2 | §5.5 | SPR-004-BE | [ ] |
| B-048 | user_badges junction table + sqlc queries | P2 | §5.5 | SPR-004-BE | [ ] |
| B-049 | device_tokens table (user_id, token, platform: ios or android, created_at) | P2 | §8 | SPR-004-BE | [ ] |
| B-050 | Gamification engine: grace day logic (preserve streak on first miss within 7 days) | P2 | §5.5 | SPR-004-BE | [ ] |
| B-051 | Gamification engine: new user WELCOME state (no penalties until has_completed_first_task) | P2 | §5.5 | SPR-004-BE | [ ] |
| B-052 | Gamification engine: overdue task penalty (-3 per OVERDUE task nightly) | P2 | §5.5 | SPR-004-BE | [ ] |
| B-053 | Badge award engine: idempotent checks for all 12 badges on task complete + nightly | P2 | §5.5 | SPR-004-BE | [ ] |
| B-054 | GET /gamification/badges — return all user_badges with earned_at | P2 | §5.5 | SPR-004-BE | [ ] |
| B-055 | Recurring task edit scope: PATCH /tasks/:id?scope=this_only or this_and_future | P1 | §5.4 | SPR-005-BE | [ ] |
| B-056 | Recurring task delete scope: DELETE /tasks/:id?scope=this_only or this_and_future | P1 | §5.4 | SPR-005-BE | [ ] |

---

## Mobile Backlog (Flutter + flutter_bloc + Dio + Hive + Rive)

| # | Feature | Priority | PRJ-001 Ref | Sprint | Status |
|:--|:--------|:---------|:------------|:-------|:-------|
| M-001 | Flutter project init (FVM, feature-first folder layout) | P0 | §8 | SPR-001-MB | [ ] |
| M-002 | Dio API client setup + base URL config (staging/prod) | P0 | §8 | SPR-001-MB | [ ] |
| M-003 | OpenAPI codegen: Dart models + Dio client from shared/openapi.yaml | P0 | §8 | SPR-001-MB | [ ] |
| M-004 | flutter_bloc scaffold: auth BLoC/Cubit | P0 | §5.1 | SPR-001-MB | [ ] |
| M-005 | flutter_secure_storage: access + refresh token persistence | P0 | §5.1 | SPR-001-MB | [ ] |
| M-006 | Dio interceptor: silent JWT refresh on 401 | P0 | §5.1 | SPR-001-MB | [ ] |
| M-007 | Login screen UI | P0 | §5.1 | SPR-001-MB | [ ] |
| M-008 | Register screen UI | P0 | §5.1 | SPR-001-MB | [ ] |
| M-009 | Forgot password screen + reset flow (deep link from Resend email) | P0 | §5.1 | SPR-001-MB | [ ] |
| M-010 | Settings screen (logout, delete account, change password) | P0 | §5.1 | SPR-001-MB | [ ] |
| M-011 | Hive local cache init (task list offline cache) | P2 | §5 | SPR-001-MB | [ ] |
| M-012 | connectivity_plus: offline detection + global offline banner | P2 | §4.4 | SPR-001-MB | [ ] |
| M-013 | Home screen gamification hero section (collapsible; sprite placeholder + tree health bar + streak counter) | P2 | §5.5 | SPR-001-MB | [ ] |
| M-014 | Task list screen (BLoC, loads from API with filter params, caches to Hive) | P0 | §3 | SPR-002-MB | [ ] |
| M-015 | Task filter/sort bottom sheet (status, priority, type, date range, sort) | P1 | §5.2 | SPR-002-MB | [ ] |
| M-016 | Task detail screen | P0 | §3 | SPR-002-MB | [ ] |
| M-017 | Create/edit task form (all fields: title, desc, address, priority, status, type, times) | P0 | §5.2 | SPR-002-MB | [ ] |
| M-018 | Drag-to-reorder task list (sort_order sync via PATCH) | P1 | §5.2 | SPR-002-MB | [ ] |
| M-019 | Task completion button — POST /tasks/:id/complete | P0 | §5.5 | SPR-002-MB | [ ] |
| M-020 | Task cancel action (swipe or menu — PATCH status=CANCELLED) | P1 | §5.2 | SPR-002-MB | [ ] |
| M-021 | Overdue task visual indicator in list (red date chip) | P1 | §5.2 | SPR-002-MB | [ ] |
| M-022 | Offline read: load task list from Hive when offline | P2 | §4.4 | SPR-002-MB | [ ] |
| M-023 | Offline write blocking: disable FAB + action buttons when offline | P2 | §4.4 | SPR-002-MB | [ ] |
| M-024 | image_picker integration (camera + gallery) | P1 | §5.3 | SPR-003-MB | [ ] |
| M-025 | Presigned URL upload: POST /attachments then upload to S3 then POST /confirm | P1 | §5.3 | SPR-003-MB | [ ] |
| M-026 | Attachment list in task detail (thumbnails for images, placeholder for video) | P1 | §5.3 | SPR-003-MB | [ ] |
| M-027 | Full-screen image viewer | P1 | §5.3 | SPR-003-MB | [ ] |
| M-028 | Video playback (video_player package) | P1 | §5.3 | SPR-003-MB | [ ] |
| M-029 | Attachment delete (swipe-to-delete with confirmation dialog) | P1 | §5.3 | SPR-003-MB | [ ] |
| M-030 | Gamification detail screen (full-size tree Rive + badge shelf + reward history) | P2 | §5.5 | SPR-004-MB | [ ] |
| M-031 | Rive sprite companion (4 states: WELCOME / HAPPY / NEUTRAL / SAD) in hero section | P2 | §5.5 | SPR-004-MB | [ ] |
| M-032 | Rive tree animation (4 states: THRIVING / HEALTHY / STRUGGLING / WITHERING) in detail screen | P2 | §5.5 | SPR-004-MB | [ ] |
| M-033 | Badge shelf widget (earned badges in colour, locked badges greyed out) | P2 | §5.5 | SPR-004-MB | [ ] |
| M-034 | Badge award toast/celebration animation on unlock | P2 | §5.5 | SPR-004-MB | [ ] |
| M-035 | Streak counter + grace day indicator in hero section | P2 | §5.5 | SPR-004-MB | [ ] |
| M-036 | Recurring task toggle in task create/edit form | P1 | §5.4 | SPR-005-MB | [ ] |
| M-037 | Recurrence schedule picker UI (daily / weekly / custom RRULE builder) | P1 | §5.4 | SPR-005-MB | [ ] |
| M-038 | Recurring task edit scope dialog (This instance vs This and all future) | P1 | §5.4 | SPR-005-MB | [ ] |
| M-039 | Display of recurring task instances in list (recurring indicator chip) | P1 | §5.4 | SPR-005-MB | [ ] |

---

> *"The backlog is a priority queue. The Architect decides what runs next."*
