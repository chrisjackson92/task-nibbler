---
id: CON-001
title: "Transport Contract — How Services Communicate"
type: reference
status: DRAFT
owner: architect
agents: [developer, tester]
tags: [architecture, contract, api, transport, cors, error-handling]
related: [BLU-003, BLU-004, CON-002, GOV-004]
created: [YYYY-MM-DD]
updated: [YYYY-MM-DD]
version: 1.0.0
---

> **BLUF:** This contract defines HOW the frontend and backend communicate: base URLs, authentication headers, error response format, CORS policy, rate limiting, and cookie behavior. Both sides MUST implement their half of this contract exactly. Any deviation is a contract violation — file an `EVO-` doc, do not self-fix.

> [!IMPORTANT]
> **This is a template.** Fill in all `[PLACEHOLDER]` sections using decisions from BLU-003 (backend) and BLU-004 (frontend). Mark this APPROVED before Developer Agents write any API integration code.

# Transport Contract

> **"The wire protocol is nobody's opinion. It's the agreement."**

---

## 1. Service Endpoints

| Service | Development URL | Port |
|:--------|:---------------|:-----|
| Backend API | `http://localhost:[PORT]` | [PORT] |
| Frontend Web | `http://localhost:[PORT]` | [PORT] |
| Database | `localhost` | [PORT] |

> Update with staging/production URLs when GOV-008 is complete.

---

## 2. Authentication

### 2.1 Token Strategy

| Property | Value |
|:---------|:------|
| Token format | [e.g., JWT (HS256) / Opaque] |
| Token location (API request) | [e.g., `Authorization: Bearer <token>` header] |
| Access token lifetime | [e.g., 15 minutes] |
| Refresh token delivery | [e.g., `httpOnly`, `Secure`, `SameSite=Strict` cookie named `refreshToken`] |
| Refresh token lifetime | [e.g., 7 days, rotated on use] |
| Token refresh endpoint | [e.g., `POST /api/auth/refresh`] |

### 2.2 Frontend Responsibilities

- Store access token **[how — e.g., in memory only, never localStorage]**
- Inject **[auth header — e.g., `Authorization: Bearer {token}`]** on every authenticated request
- On 401 response, attempt **[silent refresh strategy]**
- On refresh failure, redirect to **[login route]**

### 2.3 Backend Responsibilities

- Validate token on every protected endpoint
- Return `401 Unauthorized` for expired/invalid tokens
- **[Refresh token handling strategy — e.g., rotate on use, hash before storing]**

---

## 3. Error Response Format

All error responses MUST use a consistent shape. Adopt RFC 7807 Problem Details or equivalent:

```json
{
  "type": "https://[your-domain]/errors/[error-type]",
  "title": "Human-readable error title",
  "status": 404,
  "detail": "Specific error detail with context.",
  "instance": "/api/[resource]/[id]",
  "traceId": "00-abc123-def456-01"
}
```

### Validation Errors (422)

Validation errors extend the base shape with a field-level `errors` map:

```json
{
  "type": "https://[your-domain]/errors/validation",
  "title": "Validation failed",
  "status": 422,
  "detail": "One or more fields failed validation.",
  "errors": {
    "[field_name]": ["[Error message 1]", "[Error message 2]"],
    "[field_name]": ["[Error message]"]
  }
}
```

### Status Code Table

| Scenario | Code | Backend Returns | Frontend Handles |
|:---------|:-----|:---------------|:--------------------|
| Success (GET) | 200 | Resource DTO or array | Render data |
| Success (POST) | 201 | Created DTO + `Location` header | Navigate or refresh |
| Success (PUT/PATCH) | 200 | Updated DTO | Refresh cache |
| Success (DELETE) | 204 | Empty body | Remove from cache |
| Validation error | 422 | ProblemDetails + field errors | Show inline field errors |
| Not found | 404 | ProblemDetails | Show "not found" state |
| Unauthorized | 401 | ProblemDetails | Attempt silent refresh → redirect to login |
| Forbidden | 403 | ProblemDetails | Show "access denied" |
| Conflict (duplicate) | 409 | ProblemDetails | Show conflict message |
| Server error | 500 | ProblemDetails (no stack trace in prod) | Show generic error state |

---

## 4. CORS Policy

| Header | Value |
|:-------|:------|
| `Access-Control-Allow-Origin` | `[frontend development URL]` |
| `Access-Control-Allow-Methods` | `GET, POST, PUT, PATCH, DELETE, OPTIONS` |
| `Access-Control-Allow-Headers` | `Content-Type, Authorization` |
| `Access-Control-Allow-Credentials` | `[true if using httpOnly cookies / false otherwise]` |

### Backend Implementation

```[language]
// [Show CORS policy registration in your chosen framework]
// Example for ASP.NET Core, Express, Gin, etc.
```

### Frontend Implementation

```[language]
// [Show API client credentials configuration]
// e.g., credentials: "include" for fetch/openapi-fetch if using httpOnly cookies
```

---

## 5. Content Types

| Direction | Content-Type |
|:----------|:-------------|
| Request body | `application/json` |
| Response body (success) | `application/json` |
| Response body (error) | `application/problem+json` |
| File upload (if applicable) | `multipart/form-data` |

---

## 6. Rate Limiting

| Endpoint Category | Limit | Window |
|:------------------|:------|:-------|
| Auth endpoints | [e.g., 10 requests] | [e.g., per minute] |
| Standard endpoints | [e.g., 100 requests] | [e.g., per minute] |

Rate limit responses use `429 Too Many Requests` with a `Retry-After` header.

---

## 7. Request/Response Conventions

- **All IDs** are [e.g., UUID v7 strings / auto-increment integers] — e.g., `"3fa85f64-5717-4562-b3fc-2c963f66afa6"`
- **All timestamps** are ISO 8601 with timezone: `"2026-01-01T12:00:00Z"`
- **All dates** (no time) are ISO 8601: `"2026-01-01"`
- **Pagination** (when needed): `[define query params and response shape — e.g., ?page=1&pageSize=20]`
- **Null vs. absent fields**: [Choose one — missing fields are null / missing fields are omitted]

---

## 8. Compliance Checklist

> Architect completes before marking this document APPROVED.

- [ ] Service endpoints defined for all environments
- [ ] Auth token strategy documented (both frontend and backend responsibilities)
- [ ] Error response shape defined with examples
- [ ] HTTP status code table matches BLU-003 §5.2
- [ ] CORS policy documented with implementation examples
- [ ] Content types defined
- [ ] Rate limiting thresholds set
- [ ] ID and timestamp conventions documented
- [ ] No placeholder text (TODO, TBD) in final version

---

> *"If the frontend and backend disagree on the wire format, the contract is wrong — not the code."*
