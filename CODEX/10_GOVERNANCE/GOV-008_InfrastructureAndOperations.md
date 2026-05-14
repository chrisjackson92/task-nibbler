---
id: GOV-008
title: "Infrastructure & Operations Standard — Task Nibbles"
type: reference
status: APPROVED
owner: architect
agents: [all]
tags: [governance, standards, infrastructure, deployment, operations, fly.io]
related: [GOV-007, BLU-003, RUN-001, RUN-002, PRJ-001]
created: 2026-05-14
updated: 2026-05-14
version: 1.0.0
---

> **BLUF:** All infrastructure decisions for Task Nibbles are documented and locked here. Deployment is on Fly.io. Backend is Go + Gin in Docker. Database is Fly Postgres. File storage is AWS S3. All agents must read this document before starting any sprint.

> [!IMPORTANT]
> **Mandatory pre-reading for deployment tasks:** Before any agent works on SPR-006-OPS or any Fly.io-related task, they must read **[RUN-001 — Fly.io Platform & Development](../30_RUNBOOKS/RUN-001_Flyio_Platform_and_Development.md)** and **[RUN-002 — Fly.io Deployment Playbook](../30_RUNBOOKS/RUN-002_Flyio_Deployment_Playbook.md)**. This is a non-negotiable governance requirement, not a suggestion.

# Infrastructure & Operations Standard — Task Nibbles

---

## 1. Deployment Model

| Decision | Value |
|:---------|:------|
| **Deployment platform** | **Fly.io** |
| **Deployment mechanism** | Docker container (multi-stage Go binary) |
| **Cloud provider** | Fly.io (compute) + AWS (S3) + Resend (transactional email) |
| **Environment count** | 2: `staging`, `production` |
| **Staging hostname** | `task-nibbles-api-staging.fly.dev` |
| **Production hostname** | `api.tasknibbles.com` (custom domain via Fly certs) |
| **Primary Fly region** | `iad` (Ashburn, VA — US East) |
| **Email service** | **Resend** — password reset emails only (MVP). Free tier: 3,000 emails/month. Go SDK: `github.com/resendlabs/resend-go` |

### Environment Strategy

| Environment | App Name | Purpose | Who Deploys |
|:------------|:---------|:--------|:------------|
| **Staging** | `task-nibbles-api-staging` | Developer deploys here; Architect audits | Developer Agent (CI/CD on PR merge to `develop`) |
| **Production** | `task-nibbles-api` | Human-approved releases only | CI/CD on merge to `main`, triggered by Human |

### Fly.io Learning Requirement

> [!WARNING]
> Fly.io is a new platform for this project. Two mandatory learning runbooks exist in `30_RUNBOOKS/`:
> - **RUN-001:** Platform concepts, `fly.toml`, secrets, local dev, Docker, logging, cost model
> - **RUN-002:** First deploy checklist, deploy pipeline, environment promotion, DB migrations, rollback, CI/CD
>
> Any agent assigned a deployment task who cannot demonstrate familiarity with these documents must read them in full before executing.

---

## 2. Repository Structure

| Decision | Value |
|:---------|:------|
| **Structure** | **Monorepo** |
| **Repository name** | `task-nibbles` |

### Monorepo Layout

```
task-nibbles/                    # Git root
├── backend/                     # Go API (Gin + sqlc + pgx)
│   ├── cmd/api/main.go          # Entry point
│   ├── internal/                # Private packages (handlers, services, repos, models)
│   ├── db/                      # sqlc queries + generated code + migrations
│   ├── config/                  # Config loader (reads env vars)
│   ├── Dockerfile               # Multi-stage Go build
│   ├── fly.toml                 # Fly.io app config
│   └── go.mod
│
├── mobile/                      # Flutter app (Dart)
│   ├── lib/
│   │   ├── features/            # Feature-first folder layout
│   │   │   ├── auth/
│   │   │   ├── tasks/
│   │   │   ├── attachments/
│   │   │   └── gamification/
│   │   ├── core/                # Shared: API client, router, theme, utils
│   │   └── main.dart
│   ├── assets/
│   │   └── animations/          # Rive files (.riv): sprite.riv, tree.riv
│   └── pubspec.yaml
│
├── shared/                      # Shared artifacts (OpenAPI spec, type contracts)
│   └── openapi.yaml             # Generated from Go; consumed by Flutter codegen
│
├── CODEX/                       # CODEX project management OS
└── .github/
    └── workflows/
        ├── deploy-staging.yml   # On push to develop → deploys to staging
        └── deploy-prod.yml      # On push to main → deploys to production
```

---

## 3. Database Ownership

| Database | Owner Service | Schema Owner Agent | Notes |
|:---------|:-------------|:-------------------|:------|
| `task_nibbles` (Fly Postgres) | `backend` (Go API) | Developer-BE | Mobile app NEVER queries DB directly. All data access is via API. |

### Cross-Service Data Access

**HTTP only.** The Flutter mobile app communicates exclusively via the REST API (CON-002). There is no direct database connection from mobile. There is no message queue for MVP — all operations are synchronous HTTP.

### Postgres Cluster

| Attribute | Value |
|:----------|:------|
| **Fly app name** | `task-nibbles-db` |
| **Postgres version** | 16 |
| **Initial cluster size** | 1 node (staging + MVP) |
| **VM size** | `shared-cpu-1x` (256 MB RAM) |
| **Volume size** | 10 GB |
| **HA upgrade trigger** | When DAU > 500 or data > 5 GB |
| **Connection from API** | `postgres://api_user:***@task-nibbles-db.internal:5432/task_nibbles?sslmode=require` |

---

## 4. File Storage

| Decision | Value |
|:---------|:------|
| **Provider** | **AWS S3** |
| **Bucket name** | `task-nibbles-attachments` |
| **AWS region** | `us-east-1` |
| **Max file size** | **200 MB** per attachment |
| **Allowed MIME types** | `image/jpeg`, `image/png`, `image/heic`, `video/mp4`, `video/quicktime` |
| **Upload pattern** | **Presigned URL** — server generates URL, client uploads directly to S3 |
| **Presigned URL TTL** | 15 minutes (for upload) |
| **Download pattern** | Presigned GET URL (generated on demand, TTL 60 minutes) |
| **Public access** | ❌ Bucket is private; all access via presigned URLs |
| **Folder structure** | `{user_id}/{task_id}/{attachment_id}.{ext}` |

### Why Presigned URLs

The backend never proxies binary data. This means:
1. The API does not consume memory or bandwidth for file transfers
2. 200 MB files upload directly from the Flutter app to S3 — no API timeout risk
3. S3 handles throughput, retries, and multipart for large files

---

## 5. Shared Types Strategy

**Selected: (b) Contract-first**

The OpenAPI 3.1 spec (`shared/openapi.yaml`) is the single source of truth for request/response schemas. 

- **Backend:** Go structs are defined in `internal/models/`; the OpenAPI spec is generated from Go code annotations (using `swaggo/swag` or hand-maintained)
- **Mobile:** Flutter uses `openapi-generator` to generate Dart model classes + Dio API client from `shared/openapi.yaml`

**Rationale:** Go and Flutter are different languages. An npm package doesn't apply. Contract-first avoids duplication and keeps the OpenAPI spec as the authoritative interface document. CON-002 supplements the spec with business rules not expressible in OpenAPI.

---

## 6. Service Communication

| Decision | Value |
|:---------|:------|
| **Transport** | HTTPS (HTTP/2 via Fly.io TLS termination) |
| **Auth mechanism** | JWT Bearer token in `Authorization` header |
| **Token format** | `Authorization: Bearer <access_token>` |
| **Refresh token storage** | Flutter `flutter_secure_storage` (not cookies — mobile client) |
| **Base URL (staging)** | `https://task-nibbles-api-staging.fly.dev` |
| **Base URL (production)** | `https://api.tasknibbles.com` |
| **Content type** | `application/json` for all API requests/responses |
| **File upload** | Direct S3 via presigned URL (not through the API) |

---

## 7. Production Environment

### Runtime Configuration

| Component | Spec |
|:----------|:-----|
| **Language runtime** | Go 1.22 (compiled binary — no runtime needed in container) |
| **Container base** | `gcr.io/distroless/static-debian12` (final stage) |
| **Machine size** | `shared-cpu-1x` (256 MB RAM) — upgrade to `shared-cpu-2x` when needed |
| **TLS** | Fly.io auto-provisions Let's Encrypt certs (`force_https = true`) |
| **Process manager** | Fly.io Machine runner (no PM2/systemd needed) |
| **Reverse proxy** | Fly.io Anycast proxy (no nginx needed) |
| **Auto-stop** | `true` (MVP); set `min_machines_running = 1` for production launch |

### Required Environment Variables (set via `fly secrets set`)

| Variable | Purpose | Sensitive |
|:---------|:--------|:----------|
| `DATABASE_URL` | Fly Postgres connection string | ✅ Secret |
| `JWT_SECRET` | HMAC signing key for access tokens (256-bit) | ✅ Secret |
| `JWT_REFRESH_SECRET` | HMAC signing key for refresh tokens (256-bit) | ✅ Secret |
| `AWS_ACCESS_KEY_ID` | S3 presigned URL generation | ✅ Secret |
| `AWS_SECRET_ACCESS_KEY` | S3 presigned URL generation | ✅ Secret |
| `AWS_S3_BUCKET` | Bucket name | ✅ Secret |
| `RESEND_API_KEY` | Resend transactional email (password reset) | ✅ Secret |
| `RESEND_FROM_EMAIL` | Sender address e.g. noreply@tasknibbles.com | ✅ Secret |
| `APP_BASE_URL` | Public API base URL (used in reset email links) | ✅ Secret |
| `AWS_REGION` | `us-east-1` | Set in `fly.toml` [env] |
| `PORT` | API listen port (`8080`) | Set in `fly.toml` [env] |
| `APP_ENV` | `production` / `staging` | Set in `fly.toml` [env] |
| `LOG_LEVEL` | `info` / `debug` | Set in `fly.toml` [env] |

---

## 8. Backup & Recovery

| Decision | Value |
|:---------|:------|
| **Backup method** | Fly Postgres automatic daily snapshots |
| **Frequency** | Daily (automatic) |
| **Retention** | 7 days (Fly.io free tier default) |
| **Restore procedure** | `fly postgres backup restore BACKUP_ID --app task-nibbles-db` (see RUN-002 §5) |
| **S3 backup** | AWS S3 versioning enabled on `task-nibbles-attachments` bucket |

---

## 9. Monitoring & Observability

| Decision | Value |
|:---------|:------|
| **Error tracking** | None (MVP) — structured logs only; Sentry is a V2 addition |
| **Log aggregation** | Structured JSON logs → Fly.io log viewer (`fly logs`) |
| **Health check endpoint** | `GET /health` → `{"status":"ok","version":"x.x.x"}` — required by `fly.toml` |
| **Uptime monitoring** | None (MVP) — UptimeRobot free tier added at production launch |
| **Metrics** | Fly.io built-in dashboard (CPU, memory, request rate) |

### Health Check Contract

The Go API **must** expose:
```
GET /health
→ 200 OK
→ {"status": "ok", "version": "1.0.0", "db": "ok", "uptime_seconds": 12345}
```

This endpoint must respond in < 5 seconds. It is polled by Fly.io every 30 seconds. If it fails, Fly auto-restarts the machine.

---

## 10. Fly.io Mandatory Reading Index

> [!IMPORTANT]
> The following documents are **mandatory reading** for all agents performing deployment or infrastructure tasks. They are learning documents created for this project because Fly.io is new to the team.

| Document | When to Read | What It Covers |
|:---------|:-------------|:---------------|
| [RUN-001 — Fly.io Platform & Development](../30_RUNBOOKS/RUN-001_Flyio_Platform_and_Development.md) | Before any deployment-related task | Core concepts, fly.toml, secrets, local dev, Postgres, Docker, cost model |
| [RUN-002 — Fly.io Deployment Playbook](../30_RUNBOOKS/RUN-002_Flyio_Deployment_Playbook.md) | Before executing SPR-006-OPS | First deploy checklist, CI/CD, DB migrations, rollback, custom domain |
