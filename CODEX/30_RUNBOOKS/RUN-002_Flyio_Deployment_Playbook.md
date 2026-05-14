---
id: RUN-002
title: "Fly.io — Deployment Playbook"
type: how-to
status: APPROVED
owner: architect
agents: [all]
tags: [deployment, operations, learning, fly.io, docker, ci-cd, postgres]
related: [RUN-001, GOV-008, BLU-003]
created: 2026-05-14
updated: 2026-05-14
version: 1.0.0
---

> **BLUF:** Step-by-step playbook for deploying the Task Nibbles Go API to Fly.io. Covers first deploy, DB migrations, environment promotion, rollback, custom domain, CI/CD, and cost control. **Mandatory reading before any SPR-006-OPS task.**

> [!IMPORTANT]
> **Prerequisite: Read RUN-001 first.** This document assumes you understand Fly.io's core concepts (Apps, Machines, Volumes, Secrets, `fly.toml`). If you have not read RUN-001, stop and read it now.

# RUN-002 — Fly.io: Deployment Playbook

---

## 1. First Deploy Checklist

This is the authoritative sequence for deploying Task Nibbles to Fly.io for the first time. Execute in order.

### Step 1 — Install Fly CLI and Authenticate

```bash
# Install (Linux/macOS)
curl -L https://fly.io/install.sh | sh

# Authenticate
fly auth login
fly auth whoami          # Should print your email
```

### Step 2 — Create the Fly App (one-time)

```bash
cd backend/

# Initialize the app — this creates fly.toml if it doesn't exist yet
# DO NOT use fly launch if fly.toml already exists (it overwrites it)
fly apps create task-nibbles-api --org personal
```

### Step 3 — Provision Fly Postgres (one-time)

```bash
fly postgres create \
  --name task-nibbles-db \
  --region iad \
  --initial-cluster-size 1 \
  --vm-size shared-cpu-1x \
  --volume-size 10

# IMPORTANT: Copy the connection string from the output immediately.
# It is shown only once. Format:
# postgres://postgres:PASSWORD@task-nibbles-db.internal:5432/postgres
```

### Step 4 — Create the Application Database

```bash
# Connect to the Fly Postgres cluster
fly postgres connect --app task-nibbles-db

# Inside psql:
CREATE DATABASE task_nibbles;
CREATE USER api_user WITH ENCRYPTED PASSWORD 'strong-random-password';
GRANT ALL PRIVILEGES ON DATABASE task_nibbles TO api_user;
\q
```

### Step 5 — Set All Secrets

```bash
fly secrets set \
  DATABASE_URL="postgres://api_user:PASSWORD@task-nibbles-db.internal:5432/task_nibbles?sslmode=require" \
  JWT_SECRET="$(openssl rand -hex 32)" \
  JWT_REFRESH_SECRET="$(openssl rand -hex 32)" \
  AWS_ACCESS_KEY_ID="AKIA..." \
  AWS_SECRET_ACCESS_KEY="..." \
  AWS_S3_BUCKET="task-nibbles-attachments" \
  AWS_REGION="us-east-1" \
  --app task-nibbles-api

# Verify (values are hidden)
fly secrets list --app task-nibbles-api
```

### Step 6 — Verify `fly.toml`

Confirm `fly.toml` exists in `/backend/` and matches the template in RUN-001 §3. Key fields to verify:
- `app = "task-nibbles-api"`
- `primary_region = "iad"`
- `internal_port = 8080`
- `[checks.health]` path = `/health`

### Step 7 — Run Database Migrations

> [!WARNING]
> Always run migrations **before** deploying new code that depends on new schema. Never deploy code and migrate simultaneously — this causes downtime.

```bash
# Option A: Run migrations via fly ssh (safest for first deploy)
# First, deploy just the binary without starting the API server:
fly deploy --app task-nibbles-api

# Open a console on the running machine
fly ssh console --app task-nibbles-api

# Inside the container:
/app/api migrate up    # Requires your binary to support a 'migrate' subcommand
exit
```

**Recommended: build a `migrate` subcommand into your Go binary:**

```go
// cmd/api/main.go
func main() {
    if len(os.Args) > 1 && os.Args[1] == "migrate" {
        runMigrations()
        os.Exit(0)
    }
    startServer()
}
```

```bash
# Then in CI/CD, run migrations as a pre-deploy step:
fly ssh console --app task-nibbles-api --command "/app/api migrate up"
```

### Step 8 — Deploy

```bash
cd backend/
fly deploy --app task-nibbles-api

# Fly will:
# 1. Build the Dockerfile
# 2. Push the image to Fly's registry
# 3. Start new machines with the new image
# 4. Health-check the new machines (GET /health → 200)
# 5. Kill the old machines (zero-downtime rolling restart)
```

### Step 9 — Verify the Deploy

```bash
# Check machine status
fly status --app task-nibbles-api

# Tail logs
fly logs --app task-nibbles-api

# Test the health endpoint
curl https://task-nibbles-api.fly.dev/health
# Expected: {"status": "ok", "version": "1.0.0"}

# Test a real endpoint (auth register)
curl -X POST https://task-nibbles-api.fly.dev/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email": "test@example.com", "password": "Test1234!"}'
```

---

## 2. What Happens During `fly deploy`

Understanding the deploy pipeline prevents confusion when things fail.

```
fly deploy
    │
    ├─ 1. BUILD PHASE
    │    Fly sends your /backend directory to their remote builder.
    │    Docker BuildKit executes your Dockerfile stages.
    │    Final image is pushed to Fly's internal registry (registry.fly.io).
    │    
    ├─ 2. RELEASE PHASE  
    │    A new "release" is created (increment: v1, v2, v3...).
    │    Optional: run a release_command (e.g., migrations) before traffic shifts.
    │    
    ├─ 3. DEPLOY PHASE
    │    New Machines are started with the new image.
    │    Health checks must pass (GET /health → 200) within grace_period.
    │    
    └─ 4. CUTOVER
         Traffic shifts to new machines.
         Old machines are stopped (not deleted — kept for rollback).
         Deploy complete.
```

**If the health check fails:** Fly aborts the deploy. Old machines keep running. No downtime.

---

## 3. Environment Promotion (Dev → Staging → Prod)

For Task Nibbles MVP, we use two environments:

| Environment | App Name | Purpose |
|:------------|:---------|:--------|
| **Staging** | `task-nibbles-api-staging` | Developer deploys here first; Architect audits |
| **Production** | `task-nibbles-api` | Human approves promotion from staging |

### Deploying to Staging

```bash
fly deploy --app task-nibbles-api-staging
```

### Promoting Staging to Production

After the Architect audits staging:

```bash
# Get the image tag that's running on staging
fly releases --app task-nibbles-api-staging
# Example output: v8  registry.fly.io/task-nibbles-api-staging:deployment-01JV...

# Deploy that exact image to production (no rebuild)
fly deploy --app task-nibbles-api \
  --image registry.fly.io/task-nibbles-api-staging:deployment-01JV...
```

This guarantees production runs the exact binary that was tested on staging — no "works on staging" surprises.

---

## 4. Database Migrations on Deploy

> [!WARNING]
> This is the most common source of production incidents. Follow this pattern exactly.

### Safe Migration Pattern

```toml
# fly.toml — add a release_command
# This runs BEFORE new machines start. If it fails, deploy aborts.
[deploy]
  release_command = "/app/api migrate up"
```

With this config, every `fly deploy` automatically:
1. Runs your migration command on a temporary machine
2. If migrations succeed → proceeds to deploy new code
3. If migrations fail → aborts deploy, old code keeps running

### Migration Rules (enforce in code review)

| Rule | Reason |
|:-----|:-------|
| Migrations must be **backward compatible** | Old code runs while migration runs |
| Add columns as **nullable** first | Never add a NOT NULL column without a default in the same migration |
| Never DROP or RENAME a column in the same release as code that stops using it | Always do in two separate releases |
| Test migrations on staging DB before production | Use `fly ssh console --app task-nibbles-db-staging` |

---

## 5. Rollback Procedure

Fly keeps your last 10 releases. Rollback is instant — it re-activates old machines.

```bash
# List releases
fly releases --app task-nibbles-api
# v12  2026-05-14  ✓ ACTIVE    registry.fly.io/...:deployment-abc123
# v11  2026-05-13  ✓ COMPLETE  registry.fly.io/...:deployment-xyz789

# Roll back to v11's image
fly deploy --app task-nibbles-api \
  --image registry.fly.io/task-nibbles-api:deployment-xyz789

# Or use the dedicated rollback command (rolls back to previous release)
fly releases rollback --app task-nibbles-api
```

> [!CAUTION]
> **Database rollbacks are separate.** Fly rollback only rolls back your code. If your v12 migration added a column, rolling back to v11 code means v11 will ignore that column — which is usually fine. If the migration was destructive (dropped data), you must restore from a Postgres backup independently.

### Postgres Backup (for emergencies)

```bash
# Fly Postgres has automatic daily backups (retained 7 days on free tier)
# To restore:
fly postgres backup list --app task-nibbles-db
fly postgres backup restore BACKUP_ID --app task-nibbles-db
```

---

## 6. Custom Domain & TLS

### Step 1 — Assign a certificate to your Fly app

```bash
fly certs create api.tasknibbles.com --app task-nibbles-api

# Fly outputs a CNAME or A record to add to your DNS provider:
# CNAME api → task-nibbles-api.fly.dev
# or A record: api → <fly IP>
```

### Step 2 — Add the DNS record at your registrar

| Type | Name | Value |
|:-----|:-----|:------|
| CNAME | `api` | `task-nibbles-api.fly.dev` |

### Step 3 — Verify

```bash
fly certs check api.tasknibbles.com --app task-nibbles-api
# Wait up to 5 minutes for DNS propagation + TLS issuance (Let's Encrypt)
```

After this, HTTPS is automatically enforced (`force_https = true` in `fly.toml`).

---

## 7. CI/CD — GitHub Actions

This pipeline runs on every merge to `main`. It builds and deploys to production automatically after the test suite passes.

**Create: `.github/workflows/deploy.yml`**

```yaml
name: Deploy to Fly.io

on:
  push:
    branches: [main]
    paths:
      - "backend/**"           # Only trigger on backend changes

jobs:
  test:
    name: Run Tests
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: backend
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version: "1.22"
      - name: Run unit tests
        run: go test ./... -race -coverprofile=coverage.out
      - name: Check coverage threshold
        run: |
          COVERAGE=$(go tool cover -func=coverage.out | tail -1 | awk '{print $3}' | tr -d '%')
          if (( $(echo "$COVERAGE < 70" | bc -l) )); then
            echo "Coverage $COVERAGE% is below the 70% threshold"
            exit 1
          fi

  deploy:
    name: Deploy to Production
    runs-on: ubuntu-latest
    needs: test          # Only deploy if tests pass
    environment: production
    defaults:
      run:
        working-directory: backend
    steps:
      - uses: actions/checkout@v4

      - name: Set up Fly CLI
        uses: superfly/flyctl-actions/setup-flyctl@master

      - name: Deploy to Fly.io
        run: fly deploy --remote-only --app task-nibbles-api
        env:
          FLY_API_TOKEN: ${{ secrets.FLY_API_TOKEN }}
```

### Setting up the GitHub Secret

```bash
# Generate a deploy token (do this once)
fly tokens create deploy --app task-nibbles-api --expiry 8760h

# Add it to GitHub:
# Repository → Settings → Secrets → Actions → New secret
# Name: FLY_API_TOKEN
# Value: <token from above>
```

---

## 8. Cost Control — Auto-Stop/Start Configuration

Fly's auto-stop feature shuts down idle machines automatically, eliminating compute costs when no traffic is flowing.

| Setting | Value | When to use |
|:--------|:------|:------------|
| `auto_stop_machines = true` | Always keep on | ✅ Recommended for MVP |
| `min_machines_running = 0` | Allows full idle | MVP / low traffic |
| `min_machines_running = 1` | One machine always warm | Production with real users |

**Cold start latency:** When a machine auto-stops and a new request arrives, Fly starts a new machine in ~300ms. For a Go binary, the server is ready to handle requests in <1 second total. Acceptable for MVP; fix with `min_machines_running = 1` for production.

### Monitoring costs

```bash
# View current billing estimate
fly dashboard --app task-nibbles-api
# Navigate to: Billing → Usage

# Check machine sizes for all apps
fly machines list --app task-nibbles-api
```

---

## 9. Useful Reference — Common Fly CLI Commands

```bash
# ── App Management ─────────────────────────────────────────────────────────────
fly apps list                              # List all your apps
fly status --app task-nibbles-api          # App health + machine status
fly releases --app task-nibbles-api        # Release history

# ── Logs ───────────────────────────────────────────────────────────────────────
fly logs --app task-nibbles-api            # Tail live logs
fly logs --app task-nibbles-api -n 200     # Last 200 lines

# ── Secrets ────────────────────────────────────────────────────────────────────
fly secrets list --app task-nibbles-api    # List secret names (not values)
fly secrets set KEY=value --app ...        # Set a secret
fly secrets unset KEY --app ...            # Remove a secret

# ── Database ───────────────────────────────────────────────────────────────────
fly postgres connect --app task-nibbles-db         # Interactive psql
fly proxy 5433:5432 --app task-nibbles-db          # Tunnel for local access
fly postgres backup list --app task-nibbles-db     # List backups

# ── SSH ─────────────────────────────────────────────────────────────────────────
fly ssh console --app task-nibbles-api             # Shell inside container
fly ssh console --app task-nibbles-api --command "/app/api migrate up"

# ── Deployment ─────────────────────────────────────────────────────────────────
fly deploy --app task-nibbles-api                  # Deploy current code
fly deploy --app task-nibbles-api --image X        # Deploy specific image
fly releases rollback --app task-nibbles-api       # Rollback to previous release

# ── Scaling ────────────────────────────────────────────────────────────────────
fly scale count 2 --app task-nibbles-api           # Run 2 machines
fly scale vm shared-cpu-2x --app task-nibbles-api  # Upgrade machine size
```

---

> *"Deploy what you tested. Test what you deploy."*
>
> *Previous: [RUN-001 — Fly.io Platform Overview & Development](RUN-001_Flyio_Platform_and_Development.md)*
