---
id: CON-002
title: "API Contract — Task Nibbles REST API"
type: reference
status: APPROVED
owner: architect
agents: [developer, tester]
tags: [architecture, contract, api, routes, schemas]
related: [BLU-002, BLU-003, BLU-004, CON-001]
created: 2026-05-14
updated: 2026-05-18
version: 2.0.0
---

> **Amendment log:**
> - v1.0.0 (2026-05-14): Initial template placeholder
> - v2.0.0 (2026-05-18): Full rewrite — all routes from SPR-001-BE through SPR-009-MB documented [A-053]

> **BLUF:** This contract defines every route in the Task Nibbles API. All routes are prefixed `/api/v1`. Bearer token = JWT access token in `Authorization: Bearer <token>` header. Any additions require an `EVO-` doc and Human approval before implementation.

# API Contract — Task Nibbles REST API

> **"The route table is the law. If it's not in this document, it's not in the API."**

---

## Base URL

| Environment | Base URL |
|:------------|:---------|
| Staging | `https://task-nibbles-api-staging.fly.dev/api/v1` |
| Production | `https://task-nibbles-api.fly.dev/api/v1` |

All routes below are relative to the base URL.

---

## 1. Auth Routes

### POST `/auth/register`
- **Auth:** None
- **Rate limit:** 5 req/min per IP
- **Request:** `{ email: string, password: string, timezone?: string }`
- **Response 201:** `AuthResponse`
- **Response 409:** `EMAIL_ALREADY_EXISTS`
- **Response 422:** `VALIDATION_ERROR`

### POST `/auth/login`
- **Auth:** None
- **Rate limit:** 5 req/min per IP
- **Request:** `{ email: string, password: string }`
- **Response 200:** `AuthResponse`
- **Response 401:** `UNAUTHORIZED`

### POST `/auth/refresh`
- **Auth:** None
- **Request:** `{ refresh_token: string }`
- **Response 200:** `RefreshResponse`
- **Response 401:** `REFRESH_TOKEN_EXPIRED` | `REFRESH_TOKEN_REVOKED`

### POST `/auth/logout`
- **Auth:** Bearer token
- **Request:** `{ refresh_token: string }`
- **Response 204:** Token revoked

### POST `/auth/forgot-password`
- **Auth:** None
- **Rate limit:** 5 req/min per IP
- **Request:** `{ email: string }`
- **Response 200:** Always succeeds (prevents email enumeration)

### POST `/auth/reset-password`
- **Auth:** None
- **Request:** `{ token: string, new_password: string }`
- **Response 200:** Password updated
- **Response 401:** `TOKEN_INVALID` | `TOKEN_EXPIRED`

### POST `/auth/change-password` *(added SPR-009-MB)*
- **Auth:** Bearer token
- **Request:** `{ current_password: string, new_password: string }`
- **Response 200:** `{ message: "password updated" }`
- **Response 401:** `UNAUTHORIZED` (current password mismatch)
- **Response 422:** `VALIDATION_ERROR` (new_password < 8 chars)

### DELETE `/auth/account`
- **Auth:** Bearer token
- **Response 204:** All user data deleted (tasks, attachments, gamification, tokens)

---

## 2. User Routes

### GET `/users/me`
- **Auth:** Bearer token
- **Response 200:** `UserDto`

### PATCH `/users/me`
- **Auth:** Bearer token
- **Request:** `{ timezone?: string, display_name?: string }` *(display_name added SPR-009-MB)*
- **Response 200:** `UserDto`
- **Response 422:** `VALIDATION_ERROR`

---

## 3. Task Routes

### GET `/tasks`
- **Auth:** Bearer token
- **Query params:**
  - `status` — `pending | in_progress | completed | cancelled`
  - `priority` — `low | medium | high | urgent`
  - `type` — `personal | work | health | errand`
  - `search` — full-text search on title
  - `from` — ISO 8601 date (due_date ≥)
  - `to` — ISO 8601 date (due_date ≤)
  - `sort` — `due_date | created_at | sort_order | priority`
  - `order` — `asc | desc`
- **Response 200:** `TaskDto[]`

### POST `/tasks`
- **Auth:** Bearer token
- **Request:** `CreateTaskRequest`
- **Response 201:** `TaskDto`
- **Response 422:** `VALIDATION_ERROR`

### GET `/tasks/:id`
- **Auth:** Bearer token (owner only)
- **Response 200:** `TaskDto`
- **Response 404:** `NOT_FOUND`

### PATCH `/tasks/:id`
- **Auth:** Bearer token (owner only)
- **Query:** `?scope=this_only | this_and_future` (recurring tasks only)
- **Request:** `UpdateTaskRequest` (all fields optional)
- **Response 200:** `TaskDto`
- **Response 404:** `NOT_FOUND`

### DELETE `/tasks/:id`
- **Auth:** Bearer token (owner only)
- **Query:** `?scope=this_only | this_and_future` (recurring tasks only)
- **Response 204:** Deleted

### POST `/tasks/:id/complete`
- **Auth:** Bearer token (owner only)
- **Request:** Empty body
- **Response 200:** `{ task: TaskDto, gamification_delta: GamificationDelta }`
- **Response 404:** `NOT_FOUND`
- **Response 409:** `TASK_ALREADY_COMPLETED`

### PATCH `/tasks/:id/sort`
- **Auth:** Bearer token (owner only)
- **Request:** `{ sort_order: int }`
- **Response 200:** `TaskDto`

---

## 4. Attachment Routes

### POST `/tasks/:id/attachments`
- **Auth:** Bearer token (owner only)
- **Request:** `{ file_name: string, content_type: string, file_size: int }`
- **Response 201:** `{ attachment: AttachmentDto, upload_url: string }` (upload_url = presigned S3 PUT URL, TTL 15 min)

### POST `/tasks/:id/attachments/:attachment_id/confirm`
- **Auth:** Bearer token (owner only)
- **Request:** Empty body (call after S3 upload completes)
- **Response 200:** `AttachmentDto` (status → COMPLETE)

### GET `/tasks/:id/attachments`
- **Auth:** Bearer token (owner only)
- **Response 200:** `AttachmentDto[]`

### GET `/tasks/:id/attachments/:attachment_id/url`
- **Auth:** Bearer token (owner only)
- **Response 200:** `{ url: string }` (presigned S3 GET URL, TTL 60 min)

### DELETE `/tasks/:id/attachments/:attachment_id`
- **Auth:** Bearer token (owner only)
- **Response 204:** Deleted from S3 + DB

---

## 5. Gamification Routes

### GET `/gamification/state`
- **Auth:** Bearer token
- **Response 200:** `GamificationStateResponse`

### GET `/gamification/badges`
- **Auth:** Bearer token
- **Response 200:** `BadgeListItem[]`

### PATCH `/gamification/companion` *(added SPR-009-MB)*
- **Auth:** Bearer token
- **Request:** `{ sprite_type: "sprite_a" | "sprite_b", tree_type: "tree_a" | "tree_b" }`
- **Response 200:** `GamificationStateResponse`
- **Response 422:** `VALIDATION_ERROR` (invalid companion type)

---

## 6. System Routes

### GET `/health`
- **Auth:** None
- **Response 200:** `{ status: "ok", db: "ok", uptime_seconds: int, version: string }`

---

## N. DTO Reference

### AuthResponse
```json
{
  "access_token": "string (JWT)",
  "refresh_token": "string (opaque)",
  "user": "UserDto"
}
```

### RefreshResponse
```json
{
  "access_token": "string (JWT)",
  "refresh_token": "string (opaque, rotated)"
}
```

### UserDto
```json
{
  "id": "uuid",
  "email": "string",
  "timezone": "string (IANA, e.g. America/New_York)",
  "display_name": "string | null",
  "created_at": "datetime (ISO 8601)"
}
```

### TaskDto
```json
{
  "id": "uuid",
  "user_id": "uuid",
  "title": "string",
  "description": "string | null",
  "status": "pending | in_progress | completed | cancelled",
  "priority": "low | medium | high | urgent",
  "type": "personal | work | health | errand",
  "due_date": "datetime (ISO 8601) | null",
  "address": "string | null",
  "sort_order": "int",
  "is_overdue": "bool",
  "rrule": "string (RFC 5545 RRULE) | null",
  "recurring_rule_id": "uuid | null",
  "cancelled_at": "datetime | null",
  "completed_at": "datetime | null",
  "created_at": "datetime (ISO 8601)",
  "updated_at": "datetime (ISO 8601)"
}
```

### CreateTaskRequest
```json
{
  "title": "string (required)",
  "description": "string?",
  "priority": "low | medium | high | urgent (default: medium)",
  "type": "personal | work | health | errand (default: personal)",
  "due_date": "datetime?",
  "address": "string?",
  "rrule": "string?"
}
```

### UpdateTaskRequest
```json
{
  "title": "string?",
  "description": "string?",
  "status": "pending | in_progress | completed | cancelled?",
  "priority": "low | medium | high | urgent?",
  "type": "personal | work | health | errand?",
  "due_date": "datetime?",
  "address": "string?"
}
```

### AttachmentDto
```json
{
  "id": "uuid",
  "task_id": "uuid",
  "file_name": "string",
  "content_type": "string (MIME)",
  "file_size": "int (bytes)",
  "status": "PENDING | COMPLETE",
  "s3_key": "string",
  "created_at": "datetime (ISO 8601)"
}
```

### GamificationStateResponse
```json
{
  "user_id": "uuid",
  "streak_count": "int",
  "tree_health_score": "int (0–100)",
  "grace_active": "bool",
  "grace_used_at": "datetime | null",
  "has_completed_first_task": "bool",
  "sprite_state": "welcome | happy | neutral | sad",
  "tree_state": "thriving | healthy | struggling | withering",
  "sprite_type": "sprite_a | sprite_b",
  "tree_type": "tree_a | tree_b",
  "total_badges_earned": "int",
  "last_task_completed_at": "datetime | null",
  "updated_at": "datetime (ISO 8601)"
}
```

### GamificationDelta
```json
{
  "streak_before": "int",
  "streak_after": "int",
  "health_before": "int",
  "health_after": "int",
  "badges_awarded": "BadgeListItem[]"
}
```

### BadgeListItem
```json
{
  "id": "uuid",
  "name": "string",
  "description": "string",
  "icon": "string (emoji or icon key)",
  "trigger_type": "string",
  "earned": "bool",
  "earned_at": "datetime | null"
}
```

---

## Compliance Checklist

- [x] Every feature in PRJ-001 §3–§5 maps to at least one route
- [x] All routes have: method, path, auth requirement, request shape, all response codes
- [x] All DTOs defined in the DTO Reference section
- [x] No route added without Architect approval (SPR-009-MB additions registered here)
- [x] Response codes agree with CON-001 §3 (Status Code Table)
- [x] No content from template placeholder remains
- [x] Amendment log current

---

> *"If the route isn't in this contract, the backend shouldn't build it and the frontend shouldn't call it."*
