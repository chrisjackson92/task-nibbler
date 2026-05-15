---
id: SPR-006-OPS
title: "Sprint 6 — Fly.io Deployment & CI/CD"
type: sprint
status: MERGED
assignee: coder
agent_boot: AGT-002-BE_Backend_Developer_Agent.md
sprint_number: 6
track: ops
estimated_days: 3
blocked_by: All BE sprints (SPR-001-BE through SPR-005-BE) must pass Architect audit before production promotion
related: [GOV-008, RUN-001, RUN-002]
created: 2026-05-14
updated: 2026-05-14
---

> **BLUF:** Harden the Fly.io deployment: production Docker multi-stage build, finalized `fly.toml` configuration, full CI/CD pipeline on GitHub Actions, safe migration patterns, and custom domain + TLS. By the end, production is live at `api.tasknibbles.com` with automated staging deploys on `develop` push.

> [!IMPORTANT]
> **Mandatory pre-reading:** Read `RUN-001_Flyio_Platform_and_Development.md` AND `RUN-002_Flyio_Deployment_Playbook.md` in full before starting ANY task in this sprint. This is a governance requirement.

# Sprint 6-OPS — Fly.io Deployment & CI/CD

---

## Pre-Conditions

- [ ] Read `RUN-001_Flyio_Platform_and_Development.md` in full (**MANDATORY**)
- [ ] Read `RUN-002_Flyio_Deployment_Playbook.md` in full (**MANDATORY**)
- [ ] Read `GOV-008_InfrastructureAndOperations.md` §§7–8 in full
- [ ] All BE sprints (SPR-001-BE through SPR-005-BE) passed Architect audit
- [ ] Human has approved production promotion
- [ ] `fly` CLI installed and authenticated (`fly auth login`)
- [ ] All Fly.io secrets set for BOTH staging and production (see GOV-008 §7)

---

## Exit Criteria

- [ ] Multi-stage Dockerfile builds without errors; final image < 50 MB
- [ ] `fly deploy` to staging succeeds; `/health` returns 200 on `task-nibbles-api-staging.fly.dev`
- [ ] `fly deploy` to production succeeds; `/health` returns 200 on `task-nibbles-api.fly.dev`
- [ ] Custom domain `api.tasknibbles.com` resolves to production (DNS + TLS certificate issued)
- [ ] All 13 migration files run via `release_command` on deploy (confirmed via `fly logs`)
- [ ] GitHub Actions workflow: push to `develop` → auto-deploy to staging
- [ ] GitHub Actions workflow: push to `main` → auto-deploy to production (Human must merge to `main`)
- [ ] `fly rollback` tested on staging — confirms rollback works within 5 minutes
- [ ] Auto-stop enabled (staging only); `min_machines_running = 1` for production

---

## Task List

| BCK ID | Task | Notes |
|:-------|:-----|:------|
| B-028 | Dockerfile (multi-stage) | Stage 1: `golang:1.22-alpine` builder; Stage 2: `gcr.io/distroless/static-debian12` runner |
| B-029 | fly.toml configuration | See technical notes below |
| B-030 | DB migration on deploy (`release_command`) | `release_command = "./api migrate"` |
| B-031 | GitHub Actions CI/CD pipeline | Two workflows: staging + production |

---

## Technical Notes

### Dockerfile (Multi-Stage)
```dockerfile
# Stage 1: Build
FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o api ./cmd/api

# Stage 2: Distroless runtime
FROM gcr.io/distroless/static-debian12
COPY --from=builder /app/api /api
COPY --from=builder /app/db/migrations /db/migrations
EXPOSE 8080
ENTRYPOINT ["/api"]
```

### fly.toml (Production)
```toml
app = "task-nibbles-api"
primary_region = "iad"
kill_signal = "SIGINT"
kill_timeout = "5s"

[build]

[deploy]
  release_command = "./api migrate"

[env]
  PORT = "8080"
  APP_ENV = "production"
  LOG_LEVEL = "info"
  AWS_REGION = "us-east-1"

[http_service]
  internal_port = 8080
  force_https = true
  auto_stop_machines = false     # production: always running
  auto_start_machines = true
  min_machines_running = 1

[[http_service.checks]]
  interval = "30s"
  timeout = "5s"
  grace_period = "10s"
  method = "GET"
  path = "/api/v1/health"

[[vm]]
  memory = "256mb"
  cpu_kind = "shared"
  cpus = 1
```

### fly.toml (Staging — separate file `fly.staging.toml`)
```toml
app = "task-nibbles-api-staging"
primary_region = "iad"

[http_service]
  internal_port = 8080
  force_https = true
  auto_stop_machines = true      # staging: auto-stop saves cost
  auto_start_machines = true
  min_machines_running = 0
```

### GitHub Actions — Staging Workflow
```yaml
# .github/workflows/deploy-staging.yml
name: Deploy to Staging
on:
  push:
    branches: [develop]
    paths: [backend/**]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: superfly/flyctl-actions/setup-flyctl@master
      - name: Run tests
        run: cd backend && go test ./... -short
      - name: Deploy to staging
        run: cd backend && fly deploy --config fly.staging.toml --remote-only
        env:
          FLY_API_TOKEN: ${{ secrets.FLY_STAGING_API_TOKEN }}
```

### GitHub Actions — Production Workflow
```yaml
# .github/workflows/deploy-prod.yml
name: Deploy to Production
on:
  push:
    branches: [main]
    paths: [backend/**]

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production   # requires Human approval in GitHub Environments settings
    steps:
      - uses: actions/checkout@v4
      - uses: superfly/flyctl-actions/setup-flyctl@master
      - name: Run tests
        run: cd backend && go test ./...
      - name: Deploy to production
        run: cd backend && fly deploy --remote-only
        env:
          FLY_API_TOKEN: ${{ secrets.FLY_PROD_API_TOKEN }}
```

### Secrets to Set Before Deploy
```bash
# Run for BOTH apps (staging + production)
fly secrets set \
  DATABASE_URL="..." \
  JWT_SECRET="..." \
  JWT_REFRESH_SECRET="..." \
  AWS_ACCESS_KEY_ID="..." \
  AWS_SECRET_ACCESS_KEY="..." \
  AWS_S3_BUCKET="..." \
  RESEND_API_KEY="..." \
  RESEND_FROM_EMAIL="noreply@tasknibbles.com" \
  APP_BASE_URL="https://api.tasknibbles.com" \
  --app task-nibbles-api
```

### Custom Domain
```bash
fly certs create api.tasknibbles.com --app task-nibbles-api
# Then set DNS: CNAME api → task-nibbles-api.fly.dev
# Fly auto-provisions Let's Encrypt cert
```

See RUN-002 §6 for the full custom domain checklist.

### Rollback Testing on Staging
```bash
fly releases --app task-nibbles-api-staging
fly rollback v12 --app task-nibbles-api-staging
# Verify /health returns 200 within 2 minutes
# Then roll forward: fly deploy --config fly.staging.toml
```

---

## Testing Requirements

| Test | Type | Required |
|:-----|:-----|:---------|
| Docker image builds cleanly | CI | ✅ |
| `/health` returns 200 post-deploy (staging) | Manual | ✅ |
| `/health` returns 200 post-deploy (production) | Manual | ✅ |
| All 13 migrations ran (check `fly logs` for goose output) | Manual | ✅ |
| Staging auto-stop confirmed (machine stops after 5 min of no traffic) | Manual | ✅ |
| Rollback tested on staging | Manual | ✅ |
| CI workflow triggers on `develop` push | Automated | ✅ |

---

## Architect Audit Checklist

- [ ] Final Docker image size < 50 MB (`fly image show --app task-nibbles-api`)
- [ ] `force_https = true` in both fly.toml files
- [ ] `release_command` runs migrations before traffic cut-over (confirmed in `fly logs`)
- [ ] GitHub Actions `production` environment requires manual approval gate
- [ ] All secrets set via `fly secrets set` — no secrets in `fly.toml` or CI env vars directly
- [ ] Custom domain TLS certificate issued and showing green (`fly certs show api.tasknibbles.com`)
- [ ] Staging auto-stop verified; production `min_machines_running = 1`
- [ ] RUN-001 and RUN-002 confirmed read by executing agent (governance requirement)
