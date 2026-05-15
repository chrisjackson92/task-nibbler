# TRB-001 — fly deploy Troubleshooting Log

**Date:** 2026-05-15  
**Sprint:** SPR-001-BE  
**Outcome:** ✅ Resolved — staging deployed successfully  
**URL:** https://task-nibbles-api-staging.fly.dev/health

---

## Sequence of Errors Encountered

### Error 1 — Go version mismatch in Dockerfile

**Symptom:**
```
go: go.mod requires go >= 1.23 (running go 1.22.12; GOTOOLCHAIN=local)
```

**Root cause:** The Dockerfile specified `golang:1.22-alpine` but `go.mod` declared `go 1.23`.

**Fix:** Update `backend/Dockerfile` builder image:
```diff
-FROM golang:1.22-alpine AS builder
+FROM golang:1.23-alpine AS builder
```

**Lesson:** When upgrading Go in `go.mod`, always update the Dockerfile in the same commit.

---

### Error 2 — Missing secrets caused brutal startup failure

**Symptom:**
```
FATAL: required environment variable RESEND_API_KEY is not set
```

**Root cause:** `config.Load()` was called **before** the `migrate` subcommand check in `main()`. Since the Fly `release_command` runs the binary with `migrate` as an argument, and the server only needs `DATABASE_URL` to migrate, the hard-fatal on all env vars was premature.

**Fix:** Move the `os.Args` subcommand check **before** `config.Load()` in `main()`:
```go
func main() {
    // Check subcommand FIRST — before loading full config
    if len(os.Args) > 1 && os.Args[1] == "migrate" {
        databaseURL := os.Getenv("DATABASE_URL")
        if databaseURL == "" {
            log.Fatal("FATAL: DATABASE_URL is required for migrate")
        }
        // ... run migrations, return
    }

    // Full config load only for normal server startup
    cfg := config.Load()
    // ...
}
```

**Lesson:** Migration commands must be isolated from full application config validation.

---

### Error 3 — release_command entrypoint doubling

**Symptom:** Deploy times out with no application logs. Live logs showed:
```
INFO Preparing to run: `/api /api migrate` as 65534
```

**Root cause:** Fly.io's `release_command` is executed **as CMD**, not as a full entrypoint override. The Dockerfile's `ENTRYPOINT ["/api"]` is prepended automatically. So `release_command = "/api migrate"` became `/api /api migrate`, giving `os.Args = ["/api", "/api", "migrate"]`. Since `os.Args[1]` was `"/api"` (not `"migrate"`), the subcommand check failed, the server started, bound port 8080, and ran until Fly's 5-minute timeout killed it.

**Fix:** Remove `/api` from `release_command` — Fly prepends it from the ENTRYPOINT:
```diff
# fly.toml
[deploy]
-  release_command = "/api migrate"
+  release_command = "migrate"
```

**Result:** Fly now runs `/api` + `migrate` = `/api migrate` → `os.Args[1] == "migrate"` ✓

**Lesson:** When your Dockerfile has `ENTRYPOINT ["/binary"]`, the `release_command` in `fly.toml` should only contain the **arguments** to that binary, not the binary path itself.

---

### Error 4 — Migrations directory not present in distroless container

**Symptom:**
```
migration failed: db/migrations directory does not exist
```

**Root cause:** The Dockerfile uses a two-stage build. The runtime stage (`gcr.io/distroless/static-debian12`) only receives the compiled binary (`/api`). The `db/migrations/*.sql` files exist in the builder stage but are **not copied** to the runtime image.

**Fix:** Embed migration SQL files directly into the binary using Go's `embed` package:

1. Create `backend/db/migrations/migrations.go`:
```go
package migrations

import "embed"

//go:embed *.sql
var FS embed.FS
```

2. Update `runMigrations()` in `main.go` to use the embedded FS:
```go
import migrations "github.com/chrisjackson92/task-nibbler/backend/db/migrations"

func runMigrations(databaseURL string) error {
    // ... pool setup ...

    // Use embedded FS — no disk files needed in distroless container
    goose.SetBaseFS(migrations.FS)
    if err := goose.SetDialect("postgres"); err != nil {
        return err
    }
    return goose.Up(db, ".") // "." = root of the embedded FS
}
```

**Lesson:** Distroless containers contain only the binary. Any files needed at runtime (SQL, templates, certs) must either be copied explicitly in the Dockerfile or embedded in the binary. For migrations, embedding is preferred — the binary is self-contained and deployable anywhere.

---

### Error 5 — Wrong database password / TLS rejection

**Symptom (TLS):**
```
tls error: server refused TLS connection
```

**Symptom (auth):**
```
FATAL: password authentication failed for user "postgres" (SQLSTATE 28P01)
```

**Root cause (TLS):** Fly Postgres rejects `sslmode=require` on internal connections. The Fly private network is encrypted via WireGuard at the network layer — Postgres does not need its own TLS on top.

**Root cause (auth):** The Postgres superuser (`postgres`) password was unknown/incorrect. Multiple password attempts failed.

**Fix:**
1. Always use `sslmode=disable` for `*.internal` connections
2. Create a dedicated app user instead of using superuser:

```sql
-- Run via: fly postgres connect --app task-nibbles-db
CREATE DATABASE task_nibbles;
CREATE USER api_user WITH ENCRYPTED PASSWORD 'your-password';
GRANT ALL PRIVILEGES ON DATABASE task_nibbles TO api_user;
\c task_nibbles
GRANT ALL ON SCHEMA public TO api_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO api_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO api_user;
```

```bash
fly secrets set \
  DATABASE_URL='postgres://api_user:your-password@task-nibbles-db.internal:5432/task_nibbles?sslmode=disable' \
  --app task-nibbles-api-staging
```

**Lesson:** Never use the Postgres superuser for the application. Use a least-privilege `api_user` scoped to the application database. Always use `sslmode=disable` on Fly's internal network.

---

### Error 6 — Schema permission denied

**Symptom:**
```
migration failed: ERROR: permission denied for schema public (SQLSTATE 42501)
```

**Root cause:** In Postgres 15+, the `public` schema no longer grants CREATE privileges to all users by default. `GRANT ALL PRIVILEGES ON DATABASE` grants database-level access but does **not** grant schema-level DDL permissions.

**Fix:** After creating the user, explicitly grant schema privileges:
```sql
\c task_nibbles
GRANT ALL ON SCHEMA public TO api_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO api_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO api_user;
```

**Lesson:** `GRANT ALL ON DATABASE` ≠ `GRANT ALL ON SCHEMA public`. Always run both grants when creating an app user on Postgres 15+.

---

### Error 7 — Bash history expansion in secrets

**Symptom:**
```
bash: !@task: event not found
```

**Root cause:** Bash interprets `!` inside double-quoted strings as history expansion. A password like `TN_api_staging_2026!` contains `!`, which triggered expansion.

**Fix:** Always use **single quotes** around secrets with special characters:
```bash
# WRONG — bash history expansion triggers on !
fly secrets set DATABASE_URL="postgres://user:pass!@host/db"

# CORRECT — single quotes prevent all interpretation
fly secrets set DATABASE_URL='postgres://user:pass!@host/db'
```

**Lesson:** When setting Fly secrets containing `!`, `$`, `` ` ``, or `\`, use single quotes.

---

## Final State

```json
{
  "status": "ok",
  "db": "ok",
  "version": "1.0.0",
  "uptime_seconds": 23
}
```

**Deployment pipeline now works end-to-end:**
1. `fly deploy` → Depot builds binary with embedded migrations
2. `release_command = "migrate"` → runs `/api migrate` → goose applies 5 migrations from embedded FS → exits 0
3. App machine starts → DB pool connects → server binds :8080 → health check passes

