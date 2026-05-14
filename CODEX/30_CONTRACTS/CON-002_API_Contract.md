---
id: CON-002
title: "API Contract — Task Nibbles"
type: reference
status: APPROVED
owner: architect
agents: [coder, tester]
tags: [api, contract, routes, schema]
related: [CON-001, BLU-003, BLU-004, BLU-002]
created: 2026-05-14
updated: 2026-05-14
version: 1.0.0
---

> **BLUF:** Complete request/response schemas for all 22 API routes in Task Nibbles. This is the authoritative source for both the Go backend (handler validation) and the Flutter mobile app (generated Dio client). The OpenAPI spec at `shared/openapi.yaml` is generated from this contract.

> [!IMPORTANT]
> **Schema is locked.** The backend and mobile agents must implement these schemas exactly. Field additions require an EVO- proposal. Field renames or removals require a version bump to `/api/v2`.

# API Contract — Task Nibbles

---

## Conventions

- All `id` fields are UUID v4 strings
- All timestamps are ISO 8601 UTC: `2026-05-14T20:00:00Z`
- Omitted optional fields in responses are absent from the JSON (not `null`) unless otherwise stated
- Snake_case for all field names
- `{id}` in paths refers to the relevant resource UUID
- Auth header required for all ✅ routes (see CON-001 §2)

---

## 1. Auth Routes (`/api/v1/auth`)

### POST `/auth/register` — Create Account

**Request:**
```json
{
  "email": "user@example.com",       // required; max 320 chars; stored lowercase
  "password": "MyPass123",           // required; min 8 chars, 1 uppercase, 1 number
  "timezone": "America/New_York"     // optional; IANA timezone; default "UTC"
}
```

**Response `201`:**
```json
{
  "user": {
    "id": "uuid",
    "email": "user@example.com",
    "timezone": "America/New_York",
    "created_at": "2026-05-14T20:00:00Z"
  },
  "access_token": "eyJ...",
  "refresh_token": "abc123..."
}
```

**Errors:** `409 EMAIL_ALREADY_EXISTS`, `422 VALIDATION_ERROR`

---

### POST `/auth/login` — Authenticate

**Request:**
```json
{
  "email": "user@example.com",
  "password": "MyPass123"
}
```

**Response `200`:**
```json
{
  "user": {
    "id": "uuid",
    "email": "user@example.com",
    "timezone": "America/New_York",
    "created_at": "2026-05-14T20:00:00Z"
  },
  "access_token": "eyJ...",
  "refresh_token": "abc123..."
}
```

**Errors:** `401 UNAUTHORIZED` (wrong credentials — never distinguish email vs. password mismatch)

---

### POST `/auth/refresh` — Refresh Access Token

**Request:**
```json
{
  "refresh_token": "abc123..."
}
```

**Response `200`:**
```json
{
  "access_token": "eyJ...",
  "refresh_token": "def456..."    // new refresh token (old one is now revoked)
}
```

**Errors:** `401 REFRESH_TOKEN_EXPIRED`, `401 REFRESH_TOKEN_REVOKED`

---

### DELETE `/auth/logout` ✅ — Revoke Refresh Token

**Request:**
```json
{
  "refresh_token": "abc123..."
}
```

**Response `204` — No Content**

---

### POST `/auth/forgot-password` — Request Password Reset

**Request:**
```json
{
  "email": "user@example.com"
}
```

**Response `200`:**
```json
{
  "message": "If that email address is registered, a reset link has been sent."
}
```

> Note: Always returns 200 regardless of whether the email exists (prevents enumeration).

---

### POST `/auth/reset-password` — Set New Password

**Request:**
```json
{
  "token": "rawtoken123...",        // from the email link query param
  "new_password": "NewPass456"      // min 8 chars, 1 uppercase, 1 number
}
```

**Response `204` — No Content**

**Errors:** `401 TOKEN_INVALID` (bad/expired/used token), `422 VALIDATION_ERROR`

---

### DELETE `/auth/account` ✅ — Delete Account

**Request:** `(empty body)`

**Response `204` — No Content**

**Side effects (server-side, in transaction):**
1. Delete all `task_attachments` S3 objects (asynchronous; best-effort)
2. Delete all user rows (cascades via FK: tasks, attachments, gamification, tokens, badges, device_tokens)
3. Revoke all refresh tokens

---

## 2. Health Route

### GET `/health` — Health Check

**Auth:** ❌ None

**Response `200`:**
```json
{
  "status": "ok",
  "version": "1.0.0",
  "db": "ok",
  "uptime_seconds": 12345
}
```

**Errors:** If DB unavailable, returns `200` with `"db": "error"` (Fly.io health check still sees 200, but ops team can see DB status in logs).

---

## 3. Task Routes (`/api/v1/tasks`) ✅

### GET `/tasks` — List Tasks

**Query parameters:**

| Param | Type | Options | Default | Notes |
|:------|:-----|:--------|:--------|:------|
| `status` | string | `pending`, `completed`, `cancelled`, `overdue` | all statuses | `overdue` = calculated filter |
| `priority` | string | `low`, `medium`, `high`, `critical` | all | |
| `type` | string | `one_time`, `recurring` | all | |
| `from` | ISO 8601 | — | — | Tasks with `end_at >= from` |
| `to` | ISO 8601 | — | — | Tasks with `end_at <= to` |
| `search` | string | — | — | Full-text search on title + description |
| `sort` | string | `due_date`, `priority`, `sort_order`, `created_at` | `sort_order` | |
| `order` | string | `asc`, `desc` | `asc` | |
| `page` | integer | — | `1` | |
| `per_page` | integer | — | `50` (max 100) | |

**Response `200`:**
```json
{
  "data": [
    {
      "id": "uuid",
      "title": "Buy groceries",
      "description": "Milk, eggs, bread",
      "address": null,
      "priority": "HIGH",
      "task_type": "ONE_TIME",
      "status": "PENDING",
      "is_overdue": false,           // calculated; true when end_at < now() and status=PENDING
      "sort_order": 0,
      "start_at": null,
      "end_at": "2026-05-15T18:00:00Z",
      "completed_at": null,
      "cancelled_at": null,
      "recurring_rule_id": null,
      "is_detached": false,
      "attachment_count": 2,         // count of COMPLETE attachments; avoids N+1 fetch
      "created_at": "2026-05-14T20:00:00Z",
      "updated_at": "2026-05-14T20:00:00Z"
    }
  ],
  "meta": {
    "total": 42,
    "page": 1,
    "per_page": 50,
    "total_pages": 1
  }
}
```

---

### POST `/tasks` — Create Task

**Request:**
```json
{
  "title": "Buy groceries",            // required; max 200 chars
  "description": "Milk, eggs, bread",  // optional; max 2000 chars
  "address": "123 Main St",            // optional; max 500 chars
  "priority": "HIGH",                  // required; LOW|MEDIUM|HIGH|CRITICAL
  "task_type": "ONE_TIME",             // required; ONE_TIME|RECURRING
  "start_at": null,                    // optional; ISO 8601 UTC
  "end_at": "2026-05-15T18:00:00Z",   // optional; ISO 8601 UTC; must be after start_at
  "sort_order": 0,                     // optional; default: end of list (max sort_order + 1)
  "rrule": null                        // required if task_type=RECURRING; iCal RRULE string
}
```

**Response `201`:** Full task object (same shape as list item above, minus `attachment_count`)

**Errors:** `422 VALIDATION_ERROR`, `422 INVALID_RRULE`, `422 INVALID_DATE_RANGE`

---

### GET `/tasks/:id` — Get Task

**Response `200`:** Full task object (same as list item shape)

**Errors:** `404 TASK_NOT_FOUND`

---

### PATCH `/tasks/:id` — Update Task

Partial update — only include fields to change.

**Query parameters:**
- `scope`: `this_only` (default for ONE_TIME) | `this_and_future` (only valid for RECURRING tasks)

**Request:** Any subset of task fields (same types as POST)

```json
{
  "title": "Buy groceries — updated",
  "priority": "CRITICAL",
  "status": "CANCELLED"    // Setting status=CANCELLED sets cancelled_at server-side
}
```

**Response `200`:** Updated task object

**Errors:** `404 TASK_NOT_FOUND`, `422 VALIDATION_ERROR`

**Recurring scope logic (server-side):**
- `scope=this_only`: Sets `is_detached=TRUE` on this task row; edits apply only here
- `scope=this_and_future`: Updates `recurring_rules` row + deletes all future PENDING instances, which the nightly cron will regenerate

---

### DELETE `/tasks/:id` — Delete Task

**Query parameters:**
- `scope`: `this_only` | `this_and_future`

**Response `204` — No Content**

**Errors:** `404 TASK_NOT_FOUND`

---

### POST `/tasks/:id/complete` — Mark Task Complete

**Request:** `(empty body)`

**Response `200`:**
```json
{
  "task": {
    "id": "uuid",
    "status": "COMPLETED",
    "completed_at": "2026-05-14T20:05:00Z",
    ...
  },
  "gamification_delta": {
    "streak_count": 8,
    "tree_health_score": 72,
    "tree_health_delta": 5,           // how much tree health changed (+5)
    "grace_active": false,
    "badges_awarded": [               // badges unlocked by this completion (may be empty)
      {
        "id": "STREAK_7",
        "name": "Week Warrior",
        "emoji": "🔥",
        "description": "You maintained a 7-day streak!"
      }
    ]
  }
}
```

**Errors:** `404 TASK_NOT_FOUND`, `409` if task already COMPLETED or CANCELLED

---

### PATCH `/tasks/:id/sort-order` — Update Sort Order

**Request:**
```json
{
  "sort_order": 3
}
```

**Response `204` — No Content**

**Errors:** `404 TASK_NOT_FOUND`

---

## 4. Attachment Routes (`/api/v1/tasks/:id/attachments`) ✅

### POST `/tasks/:id/attachments` — Pre-Register Attachment

Initiates Pattern A upload (see CON-001 §9 and BLU-003 §7).

**Request:**
```json
{
  "filename": "photo.jpg",            // original filename for display
  "mime_type": "image/jpeg",          // must be in allowlist
  "size_bytes": 1234567               // declared size; validated against 200 MiB max
}
```

**Response `201`:**
```json
{
  "attachment_id": "uuid",
  "upload_url": "https://task-nibbles-attachments.s3.amazonaws.com/...",
  "expires_at": "2026-05-14T20:15:00Z"   // 15 min from now
}
```

**Errors:** `404 TASK_NOT_FOUND`, `422 ATTACHMENT_LIMIT`, `422 FILE_TOO_LARGE`, `422 INVALID_MIME_TYPE`

---

### POST `/tasks/:id/attachments/:aid/confirm` — Confirm Upload Complete

**Request:** `(empty body)`

**Response `204` — No Content**

**Errors:** `404 ATTACHMENT_NOT_FOUND`, `422 ATTACHMENT_NOT_PENDING`

---

### GET `/tasks/:id/attachments` — List Attachments

Returns only `status = COMPLETE` attachments.

**Response `200`:**
```json
{
  "data": [
    {
      "id": "uuid",
      "task_id": "uuid",
      "filename": "photo.jpg",
      "mime_type": "image/jpeg",
      "size_bytes": 1234567,
      "created_at": "2026-05-14T20:00:00Z",
      "confirmed_at": "2026-05-14T20:01:00Z"
    }
  ]
}
```

---

### GET `/tasks/:id/attachments/:aid/url` — Get Download URL

Returns a fresh presigned S3 GET URL. Caller must not cache this URL (TTL: 60 min).

**Response `200`:**
```json
{
  "url": "https://task-nibbles-attachments.s3.amazonaws.com/...",
  "expires_at": "2026-05-14T21:00:00Z"
}
```

**Errors:** `404 ATTACHMENT_NOT_FOUND`

---

### DELETE `/tasks/:id/attachments/:aid` — Delete Attachment

**Response `204` — No Content**

**Side effects:** S3 object is deleted synchronously (not deferred).

**Errors:** `404 ATTACHMENT_NOT_FOUND`

---

## 5. Gamification Routes (`/api/v1/gamification`) ✅

### GET `/gamification/state` — Get Gamification State

**Response `200`:**
```json
{
  "streak_count": 8,
  "last_active_date": "2026-05-14",       // UTC date string YYYY-MM-DD
  "grace_active": false,                   // true if streak is being preserved by grace day
  "has_completed_first_task": true,
  "tree_health_score": 72,
  "tree_state": "HEALTHY",                 // THRIVING|HEALTHY|STRUGGLING|WITHERING (calculated)
  "sprite_state": "HAPPY",                 // WELCOME|HAPPY|NEUTRAL|SAD (calculated)
  "total_badges_earned": 3
}
```

**Calculated fields (server computes, not stored):**

```
tree_state:
  THRIVING  → tree_health_score >= 75
  HEALTHY   → tree_health_score >= 50
  STRUGGLING→ tree_health_score >= 25
  WITHERING → tree_health_score < 25

sprite_state:
  WELCOME   → has_completed_first_task = false
  HAPPY     → streak_count >= 1 AND tree_health_score >= 60
  NEUTRAL   → streak_count >= 1 AND tree_health_score >= 30
  SAD       → streak_count = 0 OR tree_health_score < 30
```

---

### GET `/gamification/badges` — List User Badges

**Response `200`:**
```json
{
  "data": [
    {
      "id": "STREAK_7",
      "name": "Week Warrior",
      "emoji": "🔥",
      "description": "You maintained a 7-day streak. Your tree is starting to grow!",
      "trigger_type": "STREAK_MILESTONE",
      "earned": true,
      "earned_at": "2026-05-14T20:05:00Z"
    },
    {
      "id": "STREAK_14",
      "name": "Fortnight Fighter",
      "emoji": "⚡",
      "description": "Two weeks of consistency...",
      "trigger_type": "STREAK_MILESTONE",
      "earned": false,
      "earned_at": null
    }
  ]
}
```

Returns all 14 badges — earned ones include `earned_at`, unearned ones have `earned: false`. This allows the Flutter app to render a "progress shelf" showing locked badges greyed out.

---

## 6. Route Summary Table

| # | Method | Path | Auth | Status Codes | Backlog |
|:--|:-------|:-----|:-----|:------------|:--------|
| 1 | POST | `/auth/register` | ❌ | 201, 409, 422 | B-004 |
| 2 | POST | `/auth/login` | ❌ | 200, 401 | B-004 |
| 3 | POST | `/auth/refresh` | ❌ | 200, 401 | B-004, B-006 |
| 4 | DELETE | `/auth/logout` | ✅ | 204 | B-004 |
| 5 | POST | `/auth/forgot-password` | ❌ | 200 | B-033, B-037 |
| 6 | POST | `/auth/reset-password` | ❌ | 204, 401, 422 | B-034 |
| 7 | DELETE | `/auth/account` | ✅ | 204 | B-035 |
| 8 | GET | `/health` | ❌ | 200 | B-007 |
| 9 | GET | `/tasks` | ✅ | 200 | B-011, B-039, B-040 |
| 10 | POST | `/tasks` | ✅ | 201, 422 | B-011 |
| 11 | GET | `/tasks/:id` | ✅ | 200, 404 | B-011 |
| 12 | PATCH | `/tasks/:id` | ✅ | 200, 404, 422 | B-011, B-038 |
| 13 | DELETE | `/tasks/:id` | ✅ | 204, 404 | B-011 |
| 14 | POST | `/tasks/:id/complete` | ✅ | 200, 404, 409 | B-012 |
| 15 | PATCH | `/tasks/:id/sort-order` | ✅ | 204, 404 | B-041 |
| 16 | POST | `/tasks/:id/attachments` | ✅ | 201, 404, 422 | B-042 |
| 17 | POST | `/tasks/:id/attachments/:aid/confirm` | ✅ | 204, 404, 422 | B-043 |
| 18 | GET | `/tasks/:id/attachments` | ✅ | 200, 404 | B-027 |
| 19 | GET | `/tasks/:id/attachments/:aid/url` | ✅ | 200, 404 | B-044 |
| 20 | DELETE | `/tasks/:id/attachments/:aid` | ✅ | 204, 404 | B-028 |
| 21 | GET | `/gamification/state` | ✅ | 200 | B-038 |
| 22 | GET | `/gamification/badges` | ✅ | 200 | B-054 |

---

> *This contract is the single source of truth for both backend and mobile implementations. Any deviation must be proposed as an EVO- document.*
