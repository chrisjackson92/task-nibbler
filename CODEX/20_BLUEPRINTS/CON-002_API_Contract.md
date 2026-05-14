---
id: CON-002
title: "API Contract — What the API Looks Like"
type: reference
status: DRAFT
owner: architect
agents: [developer, tester]
tags: [architecture, contract, api, routes, schemas]
related: [BLU-002, BLU-003, BLU-004, CON-001]
created: [YYYY-MM-DD]
updated: [YYYY-MM-DD]
version: 1.0.0
---

> **Amendment log:**
> *(Record all contract changes here with date, version, and reason — e.g., "v1.1.0 (2026-06-01): Added pagination to GET /api/items — BCK-001 B-012")*

> **BLUF:** This contract defines WHAT the API looks like: every route, its request/response schema, required fields, and authorization rules. The backend MUST implement these routes. The frontend MUST call only these routes. Any additions or changes require an `EVO-` doc and Human approval.

> [!IMPORTANT]
> **This is a template.** Replace all `[PLACEHOLDER]` sections with the actual routes, schemas, and DTO definitions for your project. The Architect completes this document based on PRJ-001 feature specifications and BLU-003 architecture decisions.

# API Contract

> **"The route table is the law. If it's not in this document, it's not in the API."**

---

## How to Use This Document

1. **Backend Developer Agent:** Implement every route listed here exactly. Route structure, method, request shape, and response codes are binding. Do not add routes that aren't here.
2. **Frontend Developer Agent:** Call only routes listed here. The DTO shapes define the TypeScript types you work with.
3. **Adding a route:** Open an `EVO-NNN.md`, propose the addition, wait for Architect approval, then update this document.

---

## 1. Auth Routes

### POST `/api/auth/register`
- **Auth:** None
- **Request:** `{ [field]: [type], [field]: [type] }`
- **Response 201:** `{ accessToken: string, user: { id: [type], [fields] } }`
- **Response 409:** Account already exists
- **Response 422:** Validation errors

### POST `/api/auth/login`
- **Auth:** None
- **Request:** `{ [credential_field]: [type], [secret_field]: [type] }`
- **Response 200:** `{ accessToken: string, user: { id: [type], [fields] } }` [+ cookie if applicable]
- **Response 401:** Invalid credentials
- **Response 423:** Account locked

### POST `/api/auth/refresh`
- **Auth:** [Cookie / refresh token in body / header]
- **Request:** [Empty / `{ refreshToken: string }`]
- **Response 200:** `{ accessToken: string }` [+ new cookie if rotating]
- **Response 401:** Invalid, expired, or revoked refresh token

### POST `/api/auth/logout`
- **Auth:** Bearer token
- **Request:** Empty body
- **Response 204:** Token revoked

---

## 2. [Resource Name — e.g., "User"] Routes

> Add one section per resource domain. Document every route the application will support in MVP.

### GET `/api/[resource]`
- **Auth:** Bearer token
- **Query:** `[optional query params with types — e.g., ?status=active&page=1&pageSize=20]`
- **Response 200:** `[ResourceDto][]`

### POST `/api/[resource]`
- **Auth:** Bearer token
- **Request:** `{ [field]: [type], [optional_field]?: [type] }`
- **Response 201:** Created `[ResourceDto]` + `Location` header
- **Response 409:** [Conflict condition — e.g., duplicate name]
- **Response 422:** Validation errors

### GET `/api/[resource]/{id}`
- **Auth:** Bearer token
- **Response 200:** `[ResourceDto]`
- **Response 404:** Not found or not owned by caller

### PUT `/api/[resource]/{id}`
- **Auth:** Bearer token (owner only)
- **Request:** `{ [field]?: [type] }` — all fields optional for partial update
- **Response 200:** Updated `[ResourceDto]`
- **Response 404:** Not found

### DELETE `/api/[resource]/{id}`
- **Auth:** Bearer token (owner only)
- **Response 204:** Deleted

---

## 3. [Second Resource] Routes

*(Copy the section template above for each additional resource domain)*

---

## N. DTO Reference

> Define the canonical shape of every DTO used in request/response bodies. This is the source of truth for both the backend (what to serialize) and the frontend (what TypeScript types look like).

### [ResourceDto]

```json
{
  "id": "uuid",
  "[field]": "[type]",
  "[optional_field]": "[type]?",
  "createdAt": "datetime (ISO 8601)",
  "updatedAt": "datetime (ISO 8601)"
}
```

### [Create/UpdateRequestDto]

```json
{
  "[required_field]": "[type]",
  "[optional_field]?": "[type]"
}
```

### PaginatedResponse (if used)

```json
{
  "items": "[ResourceDto][]",
  "total": "int",
  "page": "int",
  "pageSize": "int"
}
```

---

## Compliance Checklist

> Architect completes before marking this document APPROVED.

- [ ] Every feature in PRJ-001 §3 (Core Features) maps to at least one route
- [ ] All routes have documented: method, path, auth requirement, request shape, all response codes
- [ ] All DTOs defined in the DTO Reference section
- [ ] No route added without explicit Architect/Human approval
- [ ] Response codes agree with CON-001 §3 (Status Code Table)
- [ ] No content from a previous project remains — all sections are specific to this project
- [ ] Amendment log started

---

> *"If the route isn't in this contract, the backend shouldn't build it and the frontend shouldn't call it."*
