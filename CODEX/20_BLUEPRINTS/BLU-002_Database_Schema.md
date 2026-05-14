---
id: BLU-002
title: "Database Schema Blueprint — Task Nibbles"
type: reference
status: APPROVED
owner: architect
agents: [coder]
tags: [architecture, database, schema, postgres]
related: [BLU-002-SD, BLU-003, PRJ-001, GOV-008]
created: 2026-05-14
updated: 2026-05-14
version: 1.0.0
---

> **BLUF:** Complete PostgreSQL schema for Task Nibbles. Defines all 10 tables, column types, constraints, indexes, and migration governance rules. The Backend Developer Agent builds schema migrations from this document. Changes require a new EVO- document and Human sign-off.

> [!IMPORTANT]
> **Schema is locked.** Once the Backend Developer Agent begins SPR-001-BE, changes to this document require an `EVO-NNN.md` proposal and Human approval. Never add a NOT NULL column without a default to an existing table — always use a two-migration pattern.

# Database Schema Blueprint — Task Nibbles

---

## 1. Design Decisions

| Decision | Choice | Rationale |
|:---------|:-------|:----------|
| Primary keys | `UUID v4` (all tables) | Avoids ID enumeration attacks; safe for presigned URLs |
| Timestamps | `TIMESTAMPTZ` (UTC) | All times stored in UTC; client converts for display |
| Soft delete | ❌ Not used | Hard delete + `cancelled_at` for tasks. Keeps schema simple. |
| OVERDUE status | Calculated, not stored | `status = PENDING AND end_at < now()` — no stale data risk |
| Enums | PostgreSQL `ENUM` types | Type-safe, performant, self-documenting |
| Connection pool | pgx pool (max 25 connections) | Go backend; pool managed by pgx |
| Migration tool | `goose` | Simple Go-native, supports SQL migrations, embedded in binary |
| Timezone storage | `users.timezone` (IANA string) | Required for RRULE expansion to user's local time |

---

## 2. Enum Definitions

```sql
-- Run before creating any tables that reference these types

CREATE TYPE task_priority AS ENUM ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL');
CREATE TYPE task_type     AS ENUM ('ONE_TIME', 'RECURRING');
CREATE TYPE task_status   AS ENUM ('PENDING', 'COMPLETED', 'CANCELLED');
CREATE TYPE attachment_status AS ENUM ('PENDING', 'COMPLETE');
CREATE TYPE device_platform   AS ENUM ('ios', 'android');
CREATE TYPE badge_trigger_type AS ENUM (
  'FIRST_TASK',
  'STREAK_MILESTONE',
  'VOLUME_STREAK',
  'DAILY_VOLUME',
  'TREE_HEALTH'
);
```

---

## 3. Table Definitions

### 3.1 `users`

```sql
CREATE TABLE users (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  email         VARCHAR(320) NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,               -- bcrypt hash (cost 12)
  timezone      VARCHAR(64)  NOT NULL DEFAULT 'UTC', -- IANA timezone string e.g. 'America/New_York'
  created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_users_email ON users (email);
```

**Notes:**
- `email` is stored lowercase (enforce at application layer before insert)
- `password_hash` uses bcrypt with cost factor 12
- `timezone` is used by the RRULE expansion cron to compute "daily at 9am" in the user's local time

---

### 3.2 `refresh_tokens`

```sql
CREATE TABLE refresh_tokens (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash  VARCHAR(64) NOT NULL UNIQUE, -- SHA-256 of the raw token
  expires_at  TIMESTAMPTZ NOT NULL,
  revoked_at  TIMESTAMPTZ,                -- NULL = active; NOT NULL = revoked
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_refresh_tokens_user_id   ON refresh_tokens (user_id);
CREATE INDEX idx_refresh_tokens_token_hash ON refresh_tokens (token_hash);
```

**Token rotation reuse detection:** If a `revoked_at` token is presented, revoke ALL tokens for that `user_id` immediately (assumed token theft).

---

### 3.3 `password_reset_tokens`

```sql
CREATE TABLE password_reset_tokens (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash VARCHAR(64) NOT NULL UNIQUE, -- SHA-256 of the raw token in the email link
  expires_at TIMESTAMPTZ NOT NULL,        -- 1 hour TTL
  used_at    TIMESTAMPTZ,                 -- NULL = unused; NOT NULL = consumed
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_prt_token_hash ON password_reset_tokens (token_hash);
CREATE INDEX idx_prt_user_id    ON password_reset_tokens (user_id);
```

**Rules:**
- Only one active (unused, non-expired) reset token per user at a time — previous tokens are invalidated on new request
- Token is a cryptographically random 32-byte value, stored only as its SHA-256 hash

---

### 3.4 `recurring_rules`

```sql
CREATE TABLE recurring_rules (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  rrule      VARCHAR(500) NOT NULL,   -- iCal RRULE string e.g. 'FREQ=DAILY;BYDAY=MO,WE,FR'
  is_active  BOOLEAN     NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_recurring_rules_user_id   ON recurring_rules (user_id);
CREATE INDEX idx_recurring_rules_is_active ON recurring_rules (is_active) WHERE is_active = TRUE;
```

**Notes:**
- `is_active = FALSE` when all future instances have been cancelled or the rule is deleted
- The nightly cron queries `WHERE is_active = TRUE` to know which rules to expand

---

### 3.5 `tasks`

```sql
CREATE TABLE tasks (
  id                UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  recurring_rule_id UUID          REFERENCES recurring_rules(id) ON DELETE SET NULL,
  is_detached       BOOLEAN       NOT NULL DEFAULT FALSE, -- TRUE after "this instance only" edit
  title             VARCHAR(200)  NOT NULL,
  description       TEXT,                                 -- max enforced at application layer (2000 chars)
  address           VARCHAR(500),
  priority          task_priority NOT NULL DEFAULT 'MEDIUM',
  task_type         task_type     NOT NULL DEFAULT 'ONE_TIME',
  status            task_status   NOT NULL DEFAULT 'PENDING',
  sort_order        INTEGER       NOT NULL DEFAULT 0,     -- lower = higher in list
  start_at          TIMESTAMPTZ,
  end_at            TIMESTAMPTZ,                          -- tasks with end_at < now() and status=PENDING are OVERDUE
  completed_at      TIMESTAMPTZ,                          -- set when status -> COMPLETED
  cancelled_at      TIMESTAMPTZ,                          -- set when status -> CANCELLED
  created_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_end_after_start CHECK (end_at IS NULL OR start_at IS NULL OR end_at > start_at),
  CONSTRAINT chk_completed_at    CHECK (status != 'COMPLETED' OR completed_at IS NOT NULL),
  CONSTRAINT chk_cancelled_at    CHECK (status != 'CANCELLED' OR cancelled_at IS NOT NULL)
);

-- Primary query patterns
CREATE INDEX idx_tasks_user_status      ON tasks (user_id, status);
CREATE INDEX idx_tasks_user_sort        ON tasks (user_id, sort_order);
CREATE INDEX idx_tasks_overdue          ON tasks (user_id, end_at) WHERE status = 'PENDING' AND end_at IS NOT NULL;
CREATE INDEX idx_tasks_recurring_rule   ON tasks (recurring_rule_id) WHERE recurring_rule_id IS NOT NULL;
CREATE INDEX idx_tasks_user_created     ON tasks (user_id, created_at DESC);
-- Full-text search on title + description
CREATE INDEX idx_tasks_search           ON tasks USING gin(to_tsvector('english', title || ' ' || COALESCE(description, '')));
```

**OVERDUE logic (application layer, not stored):**
```go
// Applied in the repository when reading tasks
func isOverdue(task Task) bool {
    return task.Status == TaskStatusPending &&
           task.EndAt != nil &&
           task.EndAt.Before(time.Now().UTC())
}
```

---

### 3.6 `task_attachments`

```sql
CREATE TABLE task_attachments (
  id                UUID              PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id           UUID              NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  user_id           UUID              NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status            attachment_status NOT NULL DEFAULT 'PENDING',
  s3_key            VARCHAR(500)      NOT NULL,       -- full S3 object key: {user_id}/{task_id}/{attachment_id}.{ext}
  mime_type         VARCHAR(100)      NOT NULL,
  size_bytes        BIGINT,                            -- set on confirm (client reports size; validated server-side)
  original_filename VARCHAR(255)      NOT NULL,
  created_at        TIMESTAMPTZ       NOT NULL DEFAULT NOW(),
  confirmed_at      TIMESTAMPTZ                        -- set when status -> COMPLETE
);

CREATE INDEX idx_attachments_task_status ON task_attachments (task_id, status) WHERE status = 'COMPLETE';
CREATE INDEX idx_attachments_cleanup     ON task_attachments (status, created_at) WHERE status = 'PENDING';
CREATE INDEX idx_attachments_user        ON task_attachments (user_id);

-- Max 10 attachments per task (enforced at application layer)
```

**Cleanup cron query:**
```sql
-- Delete PENDING attachments older than 1 hour (failed uploads)
DELETE FROM task_attachments
WHERE status = 'PENDING'
  AND created_at < NOW() - INTERVAL '1 hour'
RETURNING s3_key; -- use returned keys to delete from S3
```

---

### 3.7 `gamification_state`

```sql
CREATE TABLE gamification_state (
  id                       UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                  UUID    NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  streak_count             INTEGER NOT NULL DEFAULT 0,
  last_active_date         DATE,                    -- UTC date of last task completion
  grace_used_at            DATE,                    -- UTC date grace was last used (1 per 7-day window)
  has_completed_first_task BOOLEAN NOT NULL DEFAULT FALSE,
  tree_health_score        INTEGER NOT NULL DEFAULT 50 CHECK (tree_health_score >= 0 AND tree_health_score <= 100),
  created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX idx_gamification_user ON gamification_state (user_id);
```

**Lifecycle:**
- Row is created automatically when a user registers (via DB trigger or application code in registration handler)
- `has_completed_first_task = FALSE` suppresses gamification penalties (WELCOME state)
- `grace_used_at` is checked against `NOW() - 7 days` to determine if grace is available

---

### 3.8 `badges`

```sql
CREATE TABLE badges (
  id           VARCHAR(50) PRIMARY KEY,  -- e.g. 'STREAK_7', 'PRODUCTIVE_WEEK'
  name         VARCHAR(100) NOT NULL,
  description  TEXT         NOT NULL,
  emoji        VARCHAR(10)  NOT NULL,
  trigger_type badge_trigger_type NOT NULL,
  created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
```

**Seeded at deploy time.** See `BLU-002-SD` for the complete seed data. This table is read-only at runtime — badges are never added/removed via API.

---

### 3.9 `user_badges`

```sql
CREATE TABLE user_badges (
  id        UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id   UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  badge_id  VARCHAR(50) NOT NULL REFERENCES badges(id) ON DELETE CASCADE,
  earned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT uq_user_badge UNIQUE (user_id, badge_id) -- idempotent: award once only
);

CREATE INDEX idx_user_badges_user ON user_badges (user_id, earned_at DESC);
```

---

### 3.10 `device_tokens`

```sql
CREATE TABLE device_tokens (
  id         UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID            NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token      VARCHAR(500)    NOT NULL,
  platform   device_platform NOT NULL,
  created_at TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

  CONSTRAINT uq_device_token UNIQUE (user_id, token) -- prevent duplicate registrations
);

CREATE INDEX idx_device_tokens_user ON device_tokens (user_id);
```

**Note:** Device tokens are pre-provisioned for V2 FCM push notifications. No API endpoints for these in MVP — they are registered via `POST /notifications/token` added in V2.

---

## 4. Entity Relationship Summary

```
users
  ├── refresh_tokens          (1:N)
  ├── password_reset_tokens   (1:N)
  ├── recurring_rules         (1:N)
  ├── tasks                   (1:N)
  │     └── task_attachments  (1:N)
  ├── gamification_state      (1:1)
  ├── user_badges             (1:N) → badges (N:1)
  └── device_tokens           (1:N)
```

---

## 5. Migration Governance

| Rule | Detail |
|:-----|:-------|
| Tool | `goose` — migrations in `backend/db/migrations/` |
| Format | `NNNN_description.sql` (e.g., `0001_create_enums.sql`) |
| Ordering | Each migration must be backward compatible with the previous release's code |
| ADD column | Always `NULLABLE` first, or include a `DEFAULT` |
| DROP column | Two-migration pattern: first deploy code that ignores the column, then drop in next release |
| Enum changes | Add new values only (`ALTER TYPE ... ADD VALUE`) — never rename or remove |
| Rollback | Each `.sql` file must have both `-- +goose Up` and `-- +goose Down` sections |
| CI enforcement | Staging deploy runs `goose up` via Fly.io `release_command` before code starts |

### Migration Order (Initial Deployment)

```
0001_create_enums.sql
0002_create_users.sql
0003_create_refresh_tokens.sql
0004_create_password_reset_tokens.sql
0005_create_recurring_rules.sql
0006_create_tasks.sql
0007_create_task_attachments.sql
0008_create_gamification_state.sql
0009_create_badges.sql
0010_create_user_badges.sql
0011_create_device_tokens.sql
0012_seed_badges.sql
```

---

## 6. sqlc Configuration

```yaml
# backend/sqlc.yaml
version: "2"
sql:
  - engine: "postgresql"
    queries: "db/queries/"
    schema: "db/migrations/"
    gen:
      go:
        package: "db"
        out: "internal/db"
        emit_json_tags: true
        emit_params_struct_pointers: true
        emit_result_struct_pointers: true
        emit_pointers_for_null_types: true
        overrides:
          - db_type: "uuid"
            go_type: "github.com/google/uuid.UUID"
          - db_type: "timestamptz"
            go_type: "time.Time"
```

---

> *Schema changes after APPROVED status require an `EVO-NNN.md` proposal and Human approval before implementation.*
