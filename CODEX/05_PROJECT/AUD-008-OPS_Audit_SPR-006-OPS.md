---
id: AUD-008-OPS
title: "Architect Audit — SPR-006-OPS Fly.io Deployment Configuration"
type: audit
status: APPROVED
sprint: SPR-006-OPS
pr_branch: feature/B-028-B-031-flyio-deployment
commit: 6a567b2
auditor: architect
created: 2026-05-15
updated: 2026-05-15
---

> **BLUF:** SPR-006-OPS **APPROVED**. Dockerfile is a correct multi-stage CGO-free distroless build. Both fly.toml files are correctly configured (prod always-warm, staging auto-stop). Both GitHub Actions pipelines include vet, unit tests, coverage gate ≥ 70%, and Fly deploy with post-deploy health check. One informational note on staging cron behaviour. **Merge immediately — ops bootstrap runbook below.**

# Architect Audit — SPR-006-OPS

---

## Audit Scope

| Item | Value |
|:-----|:------|
| Sprint | SPR-006-OPS — Fly.io Deployment Configuration |
| PR Branch | `feature/B-028-B-031-flyio-deployment` |
| Commit | `6a567b2` |
| Files Changed | 6 |
| Contracts Audited Against | RUN-001, RUN-002, GOV-008 §7, BLU-003 |

---

## BCK Tasks Delivered

| BCK ID | Task | Status |
|:-------|:-----|:-------|
| B-028 | Multi-stage Dockerfile (distroless, CGO-free, non-root) | ✅ PASS |
| B-029 | `fly.toml` (prod) + `fly.staging.toml` — two-environment config | ✅ PASS |
| B-030 | `.dockerignore` — minimal build context | ✅ PASS |
| B-031 | GitHub Actions CI/CD — `deploy-staging.yml` + `deploy-prod.yml` | ✅ PASS |

---

## Dockerfile Audit

| Check | Result |
|:------|:-------|
| Multi-stage: `golang:1.23-alpine` builder → `distroless/static-debian12` runner | ✅ |
| `CGO_ENABLED=0 GOOS=linux GOARCH=amd64` — fully static binary | ✅ |
| `-ldflags="-w -s"` — DWARF + symbol table stripped (~35% smaller) | ✅ |
| `ca-certificates` copied — TLS works for S3, Resend, Fly Postgres | ✅ |
| `tzdata` copied — `time.LoadLocation()` works for RRULE expansion (B-026) | ✅ |
| Non-root: `USER 65534` (nobody) — GOV-008 §7 compliant | ✅ |
| `ENTRYPOINT ["/api"]` — exec form (no shell PID 1 problem) | ✅ |
| Migrations via `release_command = "/api migrate"` in fly.toml — not in Dockerfile | ✅ |
| `.dockerignore` excludes: `.env*`, `*_test.go`, `vendor/`, `fly*.toml`, `.github/` | ✅ |

---

## fly.toml Audit (Production)

| Check | Result |
|:------|:-------|
| `app = "task-nibbles-api"`, `primary_region = "iad"` | ✅ |
| `release_command = "/api migrate"` — aborts deploy if migration fails | ✅ |
| `auto_stop_machines = false` — production always warm, no cold starts | ✅ |
| `min_machines_running = 1` | ✅ |
| `force_https = true` — Fly terminates TLS; API serves HTTP internally | ✅ |
| Health check: `GET /health` every 30s, timeout 5s, grace 10s | ✅ |
| VM: `256mb` / `shared-cpu-1x` — correct for MVP | ✅ |
| No secrets in file — comment directs to `fly secrets set` | ✅ |

---

## fly.staging.toml Audit

| Check | Result |
|:------|:-------|
| `app = "task-nibbles-api-staging"` — separate app from production | ✅ |
| `auto_stop_machines = true` + `min_machines_running = 0` — cost saving | ✅ |
| `LOG_LEVEL = "debug"` — verbose staging logs | ✅ |
| Same release_command migration gate as production | ✅ |

---

## GitHub Actions Audit

### deploy-staging.yml

| Check | Result |
|:------|:-------|
| Triggers on `push → develop` when `backend/**` changes | ✅ |
| `concurrency: cancel-in-progress: true` — newest staging deploy wins | ✅ |
| `go vet ./...` | ✅ |
| `go test ./... -short -race -count=1 -coverprofile=coverage.out` | ✅ |
| Coverage gate: fails CI if < 70% | ✅ |
| `fly deploy --config fly.staging.toml --remote-only` | ✅ |
| Post-deploy health check: `curl --fail https://task-nibbles-api-staging.fly.dev/health` | ✅ |
| `deploy` job depends on `test` job via `needs: test` | ✅ |
| Uses `FLY_STAGING_API_TOKEN` secret | ✅ |

### deploy-prod.yml

| Check | Result |
|:------|:-------|
| Triggers on `push → main` when `backend/**` changes | ✅ |
| `concurrency: cancel-in-progress: false` — never cancel in-flight prod deploy | ✅ |
| Full tests (not `-short`) + race detector on production CI | ✅ |
| Coverage gate ≥ 70% | ✅ |
| `environment: production` — GitHub Environments approval gate | ✅ |
| `fly deploy --remote-only` (uses `fly.toml` by default) | ✅ |
| Post-deploy health check: `curl --fail https://task-nibbles-api.fly.dev/health` | ✅ |
| Uses `FLY_PROD_API_TOKEN` secret | ✅ |

---

## Findings

### Finding #1 — INFORMATIONAL: Nightly cron will not fire on a stopped staging machine

**Context:** `auto_stop_machines = true` + `min_machines_running = 0` means the staging machine shuts down when idle. The gocron scheduler (attachment cleanup at 00:05, recurring expansion at 00:15) runs inside the API process — if the machine is stopped at midnight, cron does not fire.

**Impact:** Staging only. Production is always warm (`min_machines_running = 1`). Nightly cron can be triggered manually on staging via `fly ssh console -a task-nibbles-api-staging` or by sending traffic to wake the machine before midnight.

**Verdict:** Expected trade-off for cost saving. No action required. Documented here for stakeholder awareness.

---

## Pending BCK Items (Not this sprint)

| BCK ID | Item | Target |
|:-------|:-----|:-------|
| B-063 | Wire `GamificationService.ApplyNightlyDecay` + `ApplyOverduePenalty` to nightly cron | SPR-007-BE |

---

## Decision

**APPROVED — merge to `develop`.**

Post-merge, all deployment bootstrap steps require Fly.io and GitHub credentials — see Ops Runbook below.
