---
id: CON-001
title: "Transport Contract — Task Nibbles"
type: reference
status: APPROVED
owner: architect
agents: [coder, tester]
tags: [api, contract, transport, auth, error-handling]
related: [CON-002, BLU-003, BLU-004, GOV-008]
created: 2026-05-14
updated: 2026-05-14
version: 1.0.0
---

> **BLUF:** This document defines the transport-level agreement between the Task Nibbles Go API and the Flutter mobile app. It governs authentication headers, request/response envelope formats, error shapes, status code conventions, file upload mechanics, pagination, and rate limiting. Both agents must implement this contract exactly — deviations require a version bump and Human approval.

# Transport Contract — Task Nibbles

---

## 1. Base URL

| Environment | Base URL |
|:------------|:---------|
| **Local dev** | `http://localhost:8080` |
| **Staging** | `https://task-nibbles-api-staging.fly.dev` |
| **Production** | `https://api.tasknibbles.com` |

All routes are prefixed `/api/v1`. Example: `GET https://api.tasknibbles.com/api/v1/tasks`

---

## 2. Authentication

### 2.1 Access Token Header

All protected routes require a JWT access token in the `Authorization` header:

```
Authorization: Bearer <access_token>
```

**Rules:**
- Tokens are short-lived (15 minutes) — the mobile client must refresh silently on 401
- The access token `sub` claim contains the `user_id` (UUID string)
- After token expiry the API returns `401 Unauthorized` with code `TOKEN_EXPIRED`
- The mobile client's `AuthInterceptor` intercepts 401 → calls `/auth/refresh` → retries the original request

### 2.2 Refresh Token

- Sent as a field in the request body to `POST /api/v1/auth/refresh` (not as a cookie)
- Mobile client stores the raw refresh token in `flutter_secure_storage`
- The server stores only the SHA-256 hash — the raw token is never logged

---

## 3. Request Format

### 3.1 Content Types

| Scenario | Request Content-Type |
|:---------|:---------------------|
| All JSON API requests | `application/json` |
| File upload | **Not sent to the API** — files go directly to S3 via presigned PUT URL |

### 3.2 Character Encoding

- All text: UTF-8
- JSON bodies must be valid JSON (no trailing commas, no comments)
- Dates/timestamps: **ISO 8601 UTC** (e.g., `2026-05-14T20:00:00Z`)

---

## 4. Response Format

### 4.1 Success Response Envelope

All successful responses return the resource directly (no wrapper object), except list endpoints.

```json
// Single resource (e.g., GET /tasks/:id, POST /tasks)
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "title": "Buy groceries",
  "status": "PENDING",
  ...
}
```

```json
// List resource (e.g., GET /tasks)
{
  "data": [ { ... }, { ... } ],
  "meta": {
    "total": 42,
    "page": 1,
    "per_page": 50
  }
}
```

### 4.2 Empty Success Responses

Operations with no response body (DELETE, logout, confirm) return:

```
HTTP 204 No Content
(empty body)
```

---

## 5. Error Response Format

All errors — validation, auth, not found, server — use this exact shape:

```json
{
  "error": {
    "code": "TASK_NOT_FOUND",
    "message": "The requested task does not exist or you do not have access to it.",
    "request_id": "01909e3c-4b2a-7f38-a4d6-123456789abc",
    "details": null
  }
}
```

| Field | Type | Always Present | Description |
|:------|:-----|:--------------|:------------|
| `code` | string | ✅ | Machine-readable error identifier (see §5.1) |
| `message` | string | ✅ | Human-readable message (safe to display in UI) |
| `request_id` | string (UUID) | ✅ | Unique per-request ID for log correlation |
| `details` | object or null | ❌ | Validation field errors (see §5.2) |

### 5.1 Error Code Reference

| HTTP Status | Code | Cause |
|:------------|:-----|:------|
| 400 | `BAD_REQUEST` | Malformed JSON or missing required field |
| 400 | `INVALID_RRULE` | Recurring rule string is not valid iCal RRULE |
| 400 | `INVALID_DATE_RANGE` | `end_at` is before `start_at` |
| 401 | `UNAUTHORIZED` | No token provided |
| 401 | `TOKEN_EXPIRED` | Access token has expired (client should refresh) |
| 401 | `TOKEN_INVALID` | Token signature is invalid or tampered |
| 401 | `REFRESH_TOKEN_EXPIRED` | Refresh token is expired — user must log in again |
| 401 | `REFRESH_TOKEN_REVOKED` | Refresh token was revoked — possible theft; user must log in |
| 403 | `FORBIDDEN` | Authenticated but not authorised for this resource |
| 404 | `NOT_FOUND` | Generic not found |
| 404 | `TASK_NOT_FOUND` | Task does not exist or belongs to another user |
| 404 | `ATTACHMENT_NOT_FOUND` | Attachment not found |
| 404 | `USER_NOT_FOUND` | User not found (internal; generally not exposed) |
| 409 | `EMAIL_ALREADY_EXISTS` | Registration with existing email |
| 422 | `VALIDATION_ERROR` | One or more fields failed validation (see details) |
| 422 | `ATTACHMENT_LIMIT` | Task already has 10 attachments |
| 422 | `FILE_TOO_LARGE` | Declared file size exceeds 200 MB |
| 422 | `INVALID_MIME_TYPE` | MIME type not in allowlist |
| 422 | `ATTACHMENT_NOT_PENDING` | Confirm called on non-PENDING attachment |
| 429 | `RATE_LIMITED` | Too many requests — see `Retry-After` header |
| 500 | `INTERNAL_ERROR` | Unexpected server error |

### 5.2 Validation Error Details

When `code = VALIDATION_ERROR`, the `details` object contains per-field errors:

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "One or more fields are invalid.",
    "request_id": "req_123",
    "details": {
      "title": ["Title is required", "Title must be 200 characters or fewer"],
      "end_at": ["end_at must be after start_at"]
    }
  }
}
```

---

## 6. HTTP Status Code Conventions

| Scenario | Status Code |
|:---------|:------------|
| Resource created successfully | `201 Created` |
| Request successful, resource returned | `200 OK` |
| Request successful, no content | `204 No Content` |
| Validation failed | `422 Unprocessable Entity` |
| Resource not found | `404 Not Found` |
| Not authenticated | `401 Unauthorized` |
| Authenticated but wrong user | `403 Forbidden` |
| Rate limited | `429 Too Many Requests` |
| Server error | `500 Internal Server Error` |

---

## 7. Rate Limiting

Auth routes are rate limited to **5 requests per minute per IP address**.

**Response headers on any request hitting rate-limited routes:**

```
X-RateLimit-Limit: 5
X-RateLimit-Remaining: 3
X-RateLimit-Reset: 1715716800   (UTC Unix timestamp when window resets)
```

**On 429 response:**

```
HTTP 429 Too Many Requests
Retry-After: 42    (seconds until the client may retry)

{
  "error": {
    "code": "RATE_LIMITED",
    "message": "Too many requests. Please wait 42 seconds before retrying.",
    "request_id": "req_abc",
    "details": null
  }
}
```

---

## 8. Pagination

List endpoints support cursor-based pagination via query parameters:

```
GET /api/v1/tasks?page=1&per_page=50
```

| Parameter | Default | Maximum | Description |
|:----------|:--------|:--------|:------------|
| `page` | `1` | — | 1-indexed page number |
| `per_page` | `50` | `100` | Items per page |

**Response meta block:**

```json
{
  "data": [...],
  "meta": {
    "total": 142,
    "page": 2,
    "per_page": 50,
    "total_pages": 3
  }
}
```

For MVP, the Flutter task list loads all tasks in one request (no pagination UI). The API still returns pagination meta to support future infinite scroll.

---

## 9. File Upload Convention

**Files are NEVER uploaded through the API.** Direct S3 upload via presigned URL only.

```
Step 1: POST /api/v1/tasks/:id/attachments
        Body: { "filename": "photo.jpg", "mime_type": "image/jpeg", "size_bytes": 1234567 }
        Response: { "attachment_id": "...", "upload_url": "https://s3.amazonaws.com/..." }

Step 2: PUT <upload_url>
        Headers: Content-Type: image/jpeg
        Body: <raw file bytes>
        (This request goes to S3, NOT to the API)

Step 3: POST /api/v1/tasks/:id/attachments/:aid/confirm
        Body: {}
        Response: 204 No Content
```

**S3 upload rules:**
- Presigned PUT URL TTL: 15 minutes from `Step 1`
- The `Content-Type` header in `Step 2` must match the `mime_type` declared in `Step 1`
- Maximum declared `size_bytes`: 209,715,200 (200 MiB)
- Allowed MIME types: `image/jpeg`, `image/png`, `image/heic`, `video/mp4`, `video/quicktime`

---

## 10. Request ID

Every API response (success and error) includes a `Request-Id` response header:

```
Request-Id: 01909e3c-4b2a-7f38-a4d6-123456789abc
```

This matches the `request_id` field in error responses. The Flutter client should log this with every failed request to enable server-side debugging.

---

## 11. CORS Policy

| Environment | Allowed Origins |
|:------------|:----------------|
| **Local dev** | `*` (all origins) |
| **Staging** | `*` (all origins) |
| **Production** | Only `tasknibbles://` (Flutter deep link scheme) + `https://api.tasknibbles.com` |

The Flutter mobile app does not use a browser, so CORS is not a concern for the mobile client. CORS is relevant only if a web dashboard is added in the future.

---

## 12. Versioning

- Current API version: `v1` (in URL path)
- Breaking changes require `v2` endpoints — `v1` routes must remain operational for 6 months
- Additive changes (new optional fields, new endpoints) do NOT require a version bump
- Contract changes must be proposed via an `EVO-NNN.md` document in the CODEX

---

> *Deviations from this contract must be proposed as an EVO- document and approved by the Architect before implementation.*
