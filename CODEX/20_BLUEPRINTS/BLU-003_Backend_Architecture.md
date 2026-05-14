---
id: BLU-003
title: "Backend Architecture Blueprint — Task Nibbles"
type: reference
status: APPROVED
owner: architect
agents: [coder, tester]
tags: [architecture, api, go, gin, backend]
related: [BLU-002, CON-001, CON-002, GOV-008, RUN-001, RUN-002]
created: 2026-05-14
updated: 2026-05-14
version: 1.0.0
---

> **BLUF:** Complete backend architecture for Task Nibbles Go API. Covers project structure, layer contracts, middleware chain, all API routes, auth strategy, S3 attachment flow, Resend email integration, go-cron nightly jobs, error handling, logging, and testing strategy. The Backend Developer Agent builds against this document.

# Backend Architecture Blueprint — Task Nibbles

---

## 1. Technology Stack

| Component | Technology | Version |
|:----------|:-----------|:--------|
| Language | Go | 1.22 |
| HTTP framework | Gin | v1.10+ |
| Database driver | pgx/v5 (connection pool) | v5 |
| Query generation | sqlc | v1.26+ |
| Migration tool | goose | v3 |
| Auth | JWT (golang-jwt/jwt v5) | v5 |
| Password hashing | bcrypt (golang.org/x/crypto) | stdlib |
| File storage | AWS S3 (aws-sdk-go-v2) | v2 |
| Email | Resend (resendlabs/resend-go) | latest |
| Cron scheduler | robfig/cron | v3 |
| Rate limiting | golang.org/x/time/rate | stdlib |
| RRULE parsing | teambition/rrule-go | latest |
| Logging | log/slog (stdlib) | Go 1.21+ |
| API docs | swaggo/swag + gin-swagger | v1.16+ |
| UUID | google/uuid | v1 |
| Configuration | env vars only (no config files) | — |
| Testing | testify/suite + sqlmock | v1 |

---

## 2. Project Structure

```
backend/
├── cmd/
│   └── api/
│       └── main.go              # Entry point — starts HTTP server or runs migrations
│
├── internal/
│   ├── config/
│   │   └── config.go            # Loads all env vars; calls log.Fatal if required vars missing
│   │
│   ├── db/                      # sqlc-generated code (DO NOT EDIT MANUALLY)
│   │   ├── db.go                # DBTX interface
│   │   ├── models.go            # Generated struct types
│   │   └── *.sql.go             # Generated query functions
│   │
│   ├── handlers/                # HTTP handlers — Gin context in, HTTP response out
│   │   ├── auth_handler.go
│   │   ├── task_handler.go
│   │   ├── attachment_handler.go
│   │   ├── gamification_handler.go
│   │   └── health_handler.go
│   │
│   ├── services/                # Business logic — no Gin types, no DB types
│   │   ├── auth_service.go
│   │   ├── task_service.go
│   │   ├── attachment_service.go
│   │   ├── gamification_service.go
│   │   └── email_service.go     # Resend wrapper
│   │
│   ├── repositories/            # Data access — wraps sqlc, returns domain types
│   │   ├── user_repository.go
│   │   ├── task_repository.go
│   │   ├── attachment_repository.go
│   │   └── gamification_repository.go
│   │
│   ├── middleware/
│   │   ├── auth.go              # JWT validation middleware
│   │   ├── rate_limit.go        # Per-IP rate limiting (auth routes: 5/min)
│   │   ├── logger.go            # Request/response structured logging
│   │   └── recovery.go          # Panic recovery + structured error response
│   │
│   ├── jobs/
│   │   └── nightly_cron.go      # go-cron nightly jobs: decay, RRULE expansion, badge eval, cleanup
│   │
│   ├── s3/
│   │   └── client.go            # AWS S3 client: presigned PUT/GET URL generation, delete
│   │
│   └── apierr/
│       └── errors.go            # Typed API error definitions (GOV-004 compliant)
│
├── db/
│   ├── migrations/              # goose SQL migration files (0001_*.sql ...)
│   └── queries/                 # sqlc .sql query files (one file per domain)
│       ├── users.sql
│       ├── tasks.sql
│       ├── attachments.sql
│       └── gamification.sql
│
├── Dockerfile                   # Multi-stage: golang:1.22-alpine builder + distroless runner
├── fly.toml                     # Fly.io app configuration
├── sqlc.yaml                    # sqlc code generation config
├── go.mod
└── go.sum
```

---

## 3. Layer Architecture

```
HTTP Request
    │
    ▼
┌──────────────────────────────────────┐
│           Gin Router                  │
│  Rate Limit → Auth → Logger → Handler│
└──────────────┬───────────────────────┘
               │  calls
               ▼
┌──────────────────────────────────────┐
│           Handler Layer              │
│  Parse request → call service        │
│  Map service result → HTTP response  │
│  (no business logic here)            │
└──────────────┬───────────────────────┘
               │  calls
               ▼
┌──────────────────────────────────────┐
│           Service Layer              │
│  Business rules live here            │
│  Orchestrates repositories           │
│  No Gin types, no DB types           │
└──────────────┬───────────────────────┘
               │  calls
               ▼
┌──────────────────────────────────────┐
│         Repository Layer             │
│  Wraps sqlc queries                  │
│  Maps DB rows → domain structs       │
│  Only place DB errors are handled    │
└──────────────┬───────────────────────┘
               │  calls
               ▼
┌──────────────────────────────────────┐
│         sqlc + pgx Pool              │
│  Type-safe generated queries         │
│  Connection pool (max 25 conns)      │
└──────────────────────────────────────┘
```

**Layer contract rules:**
- Handlers import services; services import repositories; repositories import sqlc — never skip a layer
- Handlers never import pgx or sqlc types directly
- Services never import `gin.Context`
- Repositories never contain business logic

---

## 4. Middleware Chain

Applied in this order for every request:

```
[1] Recovery middleware     — catches panics, returns 500 with structured error
[2] Logger middleware       — logs method, path, status, duration (structured JSON)
[3] CORS middleware         — mobile clients; allow all origins in dev, lock in prod
[4] Rate limit middleware   — applied selectively to /auth/* routes only (5 req/min/IP)
[5] Auth middleware         — validates JWT; injects user_id into context (applied per route group)
```

```go
// main.go — router setup
r := gin.New()
r.Use(middleware.Recovery())
r.Use(middleware.Logger())
r.Use(middleware.CORS())

// Public routes (no auth, rate-limited)
auth := r.Group("/api/v1/auth")
auth.Use(middleware.RateLimit(5, time.Minute))
{
    auth.POST("/register", authHandler.Register)
    auth.POST("/login", authHandler.Login)
    auth.POST("/refresh", authHandler.Refresh)
    auth.POST("/forgot-password", authHandler.ForgotPassword)
    auth.POST("/reset-password", authHandler.ResetPassword)
}

// Protected routes (JWT required)
api := r.Group("/api/v1")
api.Use(middleware.Auth(cfg.JWTSecret))
{
    api.DELETE("/auth/logout", authHandler.Logout)
    api.DELETE("/auth/account", authHandler.DeleteAccount)
    // ... task, attachment, gamification routes
}
```

---

## 5. API Route Map

All routes are prefixed `/api/v1`. Full request/response schemas are in `CON-002`.

### Auth

| Method | Path | Auth | Handler | Backlog |
|:-------|:-----|:-----|:--------|:--------|
| POST | `/auth/register` | ❌ | `Register` | B-004 |
| POST | `/auth/login` | ❌ | `Login` | B-004 |
| POST | `/auth/refresh` | ❌ | `Refresh` | B-004 |
| DELETE | `/auth/logout` | ✅ | `Logout` | B-004 |
| POST | `/auth/forgot-password` | ❌ | `ForgotPassword` | B-033 |
| POST | `/auth/reset-password` | ❌ | `ResetPassword` | B-034 |
| DELETE | `/auth/account` | ✅ | `DeleteAccount` | B-035 |

### Health

| Method | Path | Auth | Handler | Backlog |
|:-------|:-----|:-----|:--------|:--------|
| GET | `/health` | ❌ | `Health` | B-007 |

### Tasks

| Method | Path | Auth | Handler | Backlog |
|:-------|:-----|:-----|:--------|:--------|
| GET | `/tasks` | ✅ | `ListTasks` | B-011, B-039, B-040 |
| POST | `/tasks` | ✅ | `CreateTask` | B-011 |
| GET | `/tasks/:id` | ✅ | `GetTask` | B-011 |
| PATCH | `/tasks/:id` | ✅ | `UpdateTask` | B-011, B-038 |
| DELETE | `/tasks/:id` | ✅ | `DeleteTask` | B-011 |
| POST | `/tasks/:id/complete` | ✅ | `CompleteTask` | B-012 |
| PATCH | `/tasks/:id/sort-order` | ✅ | `UpdateSortOrder` | B-041 |

### Attachments

| Method | Path | Auth | Handler | Backlog |
|:-------|:-----|:-----|:--------|:--------|
| POST | `/tasks/:id/attachments` | ✅ | `PreRegisterAttachment` | B-042 |
| POST | `/tasks/:id/attachments/:aid/confirm` | ✅ | `ConfirmAttachment` | B-043 |
| GET | `/tasks/:id/attachments` | ✅ | `ListAttachments` | B-027 |
| GET | `/tasks/:id/attachments/:aid/url` | ✅ | `GetAttachmentURL` | B-044 |
| DELETE | `/tasks/:id/attachments/:aid` | ✅ | `DeleteAttachment` | B-028 |

### Gamification

| Method | Path | Auth | Handler | Backlog |
|:-------|:-----|:-----|:--------|:--------|
| GET | `/gamification/state` | ✅ | `GetState` | B-038 |
| GET | `/gamification/badges` | ✅ | `GetBadges` | B-054 |

---

## 6. Auth Strategy

### JWT Access Token
- Algorithm: `HMAC-SHA256` (HS256)
- Expiry: 15 minutes
- Claims: `{ sub: user_id, exp: unix_timestamp, iat: unix_timestamp }`
- Delivered in response body on login/register; client stores in memory (not localStorage)

### Refresh Token
- Format: `crypto/rand` 32 bytes → hex string (64 chars)
- Storage (server): SHA-256 hash stored in `refresh_tokens.token_hash`
- Storage (client): Flutter `flutter_secure_storage`
- Expiry: 30 days (stored in `refresh_tokens.expires_at`)
- Rotation: on every `/auth/refresh` call, old token is revoked, new token issued
- Reuse detection: if a revoked token is used → revoke ALL user tokens immediately

### Password Reset Token
- Format: `crypto/rand` 32 bytes → hex string
- Delivered via Resend email as a URL parameter: `https://app.tasknibbles.com/reset-password?token=<raw>`
- Server stores SHA-256 hash in `password_reset_tokens.token_hash`
- TTL: 1 hour; single-use (`used_at` set on consumption)

### Rate Limiting
```go
// middleware/rate_limit.go
// Uses token bucket per IP address
// Auth routes: 5 requests per minute per IP
// Returns 429 Too Many Requests with Retry-After header
```

---

## 7. S3 Attachment Flow (Pattern A — Pre-register)

```
Client                    API Server              AWS S3
  │                           │                      │
  │ POST /attachments          │                      │
  │ {filename, mime_type}      │                      │
  ├──────────────────────────>│                      │
  │                           │ INSERT task_attachments (PENDING)
  │                           │ GeneratePresignedPutURL (TTL: 15min)
  │                           │                      │
  │<──────────────────────────│                      │
  │ {attachment_id, upload_url}│                      │
  │                           │                      │
  │ PUT <upload_url>           │                      │
  │ (raw file bytes)           │                      │
  ├───────────────────────────────────────────────>  │
  │                                                   │ 200 OK
  │<───────────────────────────────────────────────── │
  │                           │                      │
  │ POST /attachments/:id/confirm                     │
  │ {size_bytes}              │                      │
  ├──────────────────────────>│                      │
  │                           │ UPDATE task_attachments SET status=COMPLETE
  │<──────────────────────────│                      │
  │ {attachment (COMPLETE)}   │                      │
```

**S3 key format:** `{user_id}/{task_id}/{attachment_id}.{ext}`
**Presigned PUT URL:** 15-minute TTL, `Content-Type` locked to declared MIME type
**Presigned GET URL:** 60-minute TTL, generated on-demand per `GET /attachments/:id/url`

---

## 8. Resend Email Integration (Password Reset)

```go
// internal/services/email_service.go
import "github.com/resendlabs/resend-go"

type EmailService struct {
    client    *resend.Client
    fromEmail string
    baseURL   string
}

func (s *EmailService) SendPasswordReset(ctx context.Context, toEmail, rawToken string) error {
    resetURL := fmt.Sprintf("%s/reset-password?token=%s", s.baseURL, rawToken)

    _, err := s.client.Emails.Send(&resend.SendEmailRequest{
        From:    s.fromEmail, // e.g. "Task Nibbles <noreply@tasknibbles.com>"
        To:      []string{toEmail},
        Subject: "Reset your Task Nibbles password",
        Html:    buildResetEmailHTML(resetURL), // simple branded template
    })
    return err
}
```

**Security rules:**
- The API always returns `200 OK` on `POST /auth/forgot-password` regardless of whether the email exists (prevents email enumeration)
- The raw token is **never logged**
- Only the SHA-256 hash is stored in the database

---

## 9. Nightly Cron Jobs (go-cron)

All jobs run at `00:05 UTC` to avoid midnight boundary race conditions.

```go
// internal/jobs/nightly_cron.go
func RegisterJobs(c *cron.Cron, deps *JobDeps) {
    c.AddFunc("5 0 * * *", func() {
        ctx, cancel := context.WithTimeout(context.Background(), 30*time.Minute)
        defer cancel()

        runJob(ctx, "gamification_decay",    deps.GamificationJob.RunDecay)
        runJob(ctx, "overdue_penalty",       deps.GamificationJob.ApplyOverduePenalties)
        runJob(ctx, "badge_evaluation",      deps.BadgeJob.EvaluateAllUsers)
        runJob(ctx, "rrule_expansion",       deps.RecurringJob.ExpandRules)
        runJob(ctx, "attachment_cleanup",    deps.AttachmentJob.CleanupPending)
    })
}
```

### Job: `gamification_decay`
- For each user where `last_active_date < TODAY` and `has_completed_first_task = TRUE`:
  - Check grace day: if `grace_used_at` is NULL or older than 7 days → consume grace, preserve streak
  - Otherwise → reset `streak_count = 0`, apply `-10` to `tree_health_score` (floor 0)

### Job: `overdue_penalty`
- For each task where `status = PENDING AND end_at < NOW()`:
  - Apply `-3` to owning user's `tree_health_score` (floor 0)

### Job: `badge_evaluation`
- Evaluate volume × streak badges (`CONSISTENT_WEEK/MONTH`, `PRODUCTIVE_WEEK/MONTH`, `TREE_SUSTAINED`)
- Insert into `user_badges` where condition met and not already awarded

### Job: `rrule_expansion`
- For each `recurring_rules where is_active = TRUE`:
  - Parse RRULE using user's timezone
  - Generate occurrences for next 30 days
  - Insert `tasks` rows for each date not already having an instance (idempotent)

### Job: `attachment_cleanup`
- `DELETE FROM task_attachments WHERE status = 'PENDING' AND created_at < NOW() - '1 hour'`
- For each deleted row's `s3_key`, call `s3.DeleteObject`

---

## 10. Error Handling (GOV-004 Compliant)

All errors are returned in a consistent JSON envelope:

```json
{
  "error": {
    "code": "TASK_NOT_FOUND",
    "message": "The requested task does not exist or you do not have access to it.",
    "request_id": "req_abc123"
  }
}
```

Error codes are defined in `internal/apierr/errors.go`:

```go
var (
    ErrUnauthorized     = &APIError{Code: "UNAUTHORIZED",      Status: 401}
    ErrForbidden        = &APIError{Code: "FORBIDDEN",         Status: 403}
    ErrNotFound         = &APIError{Code: "NOT_FOUND",         Status: 404}
    ErrTaskNotFound     = &APIError{Code: "TASK_NOT_FOUND",    Status: 404}
    ErrAttachmentLimit  = &APIError{Code: "ATTACHMENT_LIMIT",  Status: 422}
    ErrFileTooLarge     = &APIError{Code: "FILE_TOO_LARGE",    Status: 422}
    ErrInvalidMIME      = &APIError{Code: "INVALID_MIME_TYPE", Status: 422}
    ErrRateLimited      = &APIError{Code: "RATE_LIMITED",      Status: 429}
    ErrInternalServer   = &APIError{Code: "INTERNAL_ERROR",    Status: 500}
    // ... full list in source
)
```

The `request_id` is a UUID generated per-request by the logger middleware and injected into the Gin context. Every log line includes this ID for cross-referencing.

---

## 11. Logging Strategy (GOV-006 Compliant)

Using `log/slog` with `slog.NewJSONHandler` — all log output is structured JSON.

```go
// Every log line follows this pattern
slog.InfoContext(ctx, "task completed",
    "request_id", requestID,
    "user_id",    userID,
    "task_id",    taskID,
    "streak",     newStreak,
    "tree_health", newTreeHealth,
)
```

**Log levels:**
- `DEBUG` — detailed query params, token validation steps (dev/staging only)
- `INFO` — request completed, task created, badge awarded, cron job ran
- `WARN` — rate limit hit, token reuse detected, S3 delete failed (non-fatal)
- `ERROR` — DB error, S3 error, email send failure, unhandled panic

---

## 12. Testing Strategy (GOV-002 Compliant)

| Layer | Approach | Tool |
|:------|:---------|:-----|
| Handlers | Unit tests with `httptest.NewRecorder` + mock services | `testify/mock` |
| Services | Unit tests with mock repositories | `testify/mock` |
| Repositories | Integration tests against real Postgres (test DB) | `testify/suite` + Docker Compose |
| Cron jobs | Unit tests with fixtures for edge cases (grace day, streak reset, badge award) | `testify/suite` |
| Auth flow | Integration tests: register → login → use token → refresh → logout | `httptest` |
| Coverage target | ≥ 70% (enforced in CI) | `go test -coverprofile` |

---

## 13. Entry Point — `main.go`

```go
func main() {
    cfg := config.Load() // panics if required env vars missing

    if len(os.Args) > 1 && os.Args[1] == "migrate" {
        runMigrations(cfg.DatabaseURL)
        return
    }

    db := setupDatabase(cfg)
    s3 := setupS3(cfg)
    resend := setupResend(cfg)

    // Wire dependencies
    repos := repositories.NewAll(db)
    services := services.NewAll(repos, s3, resend, cfg)
    handlers := handlers.NewAll(services)

    // Start cron
    c := cron.New()
    jobs.RegisterJobs(c, jobs.NewDeps(services))
    c.Start()
    defer c.Stop()

    // Start HTTP server
    r := setupRouter(handlers, cfg)
    r.Run(":" + cfg.Port)
}
```

---

> *Read next: CON-001 (Transport Contract), CON-002 (API Contract)*
