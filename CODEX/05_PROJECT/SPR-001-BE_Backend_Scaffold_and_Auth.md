---
id: SPR-001-BE
title: "Sprint 1 — Backend Scaffold & Auth"
type: sprint
status: DONE
assignee: coder
agent_boot: AGT-002-BE_Backend_Developer_Agent.md
sprint_number: 1
track: backend
estimated_days: 5
related: [BLU-002, BLU-003, CON-001, CON-002, GOV-008, RUN-001]
created: 2026-05-14
updated: 2026-05-14
audit: AUD-001-BE_Audit_SPR-001-BE.md
audit_result: APPROVED_WITH_NOTES
---

> **BLUF:** Stand up the entire Go backend skeleton and implement all authentication endpoints. By the end of this sprint, the API is running on staging, health check passes, all auth flows work (register, login, refresh, logout, forgot-password, reset-password, delete-account), and Fly.io staging deployment is alive.

# Sprint 1-BE — Backend Scaffold & Auth

---

## Pre-Conditions (Must be TRUE before starting)

- [ ] Read `AGT-002-BE_Backend_Developer_Agent.md` in full
- [ ] Read `BLU-003_Backend_Architecture.md` in full
- [ ] Read `CON-001_Transport_Contract.md` in full
- [ ] Read `CON-002_API_Contract.md` §1 (Auth routes) and §2 (Health route) in full
- [ ] Read `BLU-002_Database_Schema.md` §§3.1–3.3 (users, refresh_tokens, password_reset_tokens)
- [ ] Read `RUN-001_Flyio_Platform_and_Development.md` in full
- [ ] Local Postgres is running (Docker Compose or direct)

---

## Exit Criteria (Sprint is DONE when ALL pass)

- [x] `GET /health` returns `{"status":"ok","db":"ok"}` with 200
- [x] `POST /auth/register` creates user, returns tokens
- [x] `POST /auth/login` validates credentials, returns tokens
- [x] `POST /auth/refresh` rotates refresh token
- [x] `DELETE /auth/logout` revokes refresh token
- [x] `POST /auth/forgot-password` sends Resend email (verified in Resend dashboard)
- [x] `POST /auth/reset-password` sets new password
- [x] `DELETE /auth/account` deletes all user rows in a transaction
- [x] 401 returned when refresh token is replayed after rotation (reuse detection)
- [x] All auth routes return 429 after 5 requests/min (rate limit confirmed)
- [x] All responses match the CON-001 §5 error envelope shape
- [x] All migrations run cleanly via `goose up`
- [x] `go test ./...` passes with ≥ 70% coverage on auth and middleware packages
- [x] Swagger/OpenAPI spec renders at `/swagger/index.html`
- [ ] Staging deployment live on `task-nibbles-api-staging.fly.dev` — **PENDING Human deploy after merge**

---

## Task List

| BCK ID | Task | Notes |
|:-------|:-----|:------|
| B-001 | Go module init, project structure, Gin router scaffold | Use structure from BLU-003 §2 exactly |
| B-002 | PostgreSQL connection (pgx pool) | Max 25 connections; use config.Load() |
| B-003 | sqlc setup + goose migration tooling | See BLU-002 §6 for sqlc.yaml config |
| B-004 | Auth endpoints: register, login, refresh, logout | See CON-002 §1 for exact schemas |
| B-005 | JWT middleware (access + refresh token validation) | HS256; `sub` = user_id UUID string |
| B-006 | Global error handling middleware | CON-001 §5 envelope; `request_id` in every response |
| B-007 | `GET /health` endpoint | Returns `{"status","version","db","uptime_seconds"}` |
| B-008 | OpenAPI / Swagger doc generation (swaggo/swag) | Serves at `/swagger/index.html` |
| B-009 | Structured JSON logging (slog) | `LOG_LEVEL` env var controls verbosity |
| B-032 | `refresh_tokens` table migration + sqlc queries | token_hash = SHA-256(raw_token); see BLU-002 §3.2 |
| B-033 | `POST /auth/forgot-password` (Resend integration) | Always returns 200; never enumerate emails |
| B-034 | `POST /auth/reset-password` | 1-hour TTL; single-use token |
| B-035 | `DELETE /auth/account` | Transaction: delete S3 objects (async) + all DB rows |
| B-036 | Rate limiting middleware | 5 req/min per IP on `/auth/*`; return 429 with `Retry-After` |
| B-037 | Resend Go SDK + password reset email template | See BLU-003 §8; never log raw tokens |

---

## Technical Notes

### Password Reset Token Security
```go
// Generate raw token
rawBytes := make([]byte, 32)
rand.Read(rawBytes)
rawToken := hex.EncodeToString(rawBytes)  // 64-char string — sent in email

// Store only the hash
hash := sha256.Sum256([]byte(rawToken))
tokenHash := hex.EncodeToString(hash[:])  // stored in DB
```

### Refresh Token Reuse Detection
If `token_hash` is found in `refresh_tokens` but `revoked_at IS NOT NULL` — this is token reuse after rotation (possible theft). **Revoke ALL refresh tokens for that user immediately** and return `401 REFRESH_TOKEN_REVOKED`.

### `DELETE /auth/account` Transaction Pattern
1. Collect all `s3_key` values from `task_attachments` for this user
2. Begin DB transaction
3. Delete user row (cascades to all FK children)
4. Commit transaction
5. After commit (outside transaction): delete S3 objects asynchronously — log failures, don't surface to user

### Initial Migrations to Create
```
backend/db/migrations/
  0001_create_enums.sql
  0002_create_users.sql
  0003_create_refresh_tokens.sql
  0004_create_password_reset_tokens.sql
```
(Tables for tasks, attachments, gamification, badges come in later sprints)

### fly.toml `release_command`
```toml
[deploy]
  release_command = "./api migrate"
```
This runs `goose up` before traffic switches to the new deployment. See RUN-002 §4 for full migration safety pattern.

---

## Testing Requirements

| Test | Type | Required |
|:-----|:-----|:---------|
| `TestRegister_Success` | Integration | ✅ |
| `TestRegister_DuplicateEmail` | Integration | ✅ |
| `TestLogin_WrongPassword` | Integration | ✅ |
| `TestRefresh_TokenRotation` | Integration | ✅ |
| `TestRefresh_ReuseDetection` | Unit | ✅ |
| `TestRateLimit_AuthRoutes` | Integration | ✅ |
| `TestDeleteAccount_CascadesAll` | Integration | ✅ |
| `TestJWT_ExpiredToken` | Unit | ✅ |
| `TestHealth_DBOk` | Integration | ✅ |

---

## Architect Audit Checklist

> Audit completed: 2026-05-14. Full report: [AUD-001-BE_Audit_SPR-001-BE.md](AUD-001-BE_Audit_SPR-001-BE.md)

- [x] All responses match CON-001 §5 error envelope exactly
- [x] `request_id` present in every response header and error body
- [x] No raw tokens or secrets appear in any log line
- [x] `refresh_tokens` reuse detection confirmed via test
- [x] Rate limiting confirmed at exactly 5 req/min per IP
- [x] `forgot-password` returns 200 for non-existent email (email enumeration prevention)
- [x] Swagger UI renders all 8 auth routes with correct schemas
- [ ] Staging URL responds to `GET /health` with 200 — **PENDING: Human must run `fly deploy` after merge**
