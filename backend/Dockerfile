# ──────────────────────────────────────────────────────────────────────────────
# Task Nibbles API — Multi-Stage Dockerfile
# B-028 — SPR-006-OPS
#
# Stage 1 (builder): Full Go toolchain compiles a CGO-free static binary.
# Stage 2 (runner):  Distroless runtime — no shell, no package manager.
#                    Attack surface ≈ binary + CA certs + timezone data only.
#
# Migrations are embedded via go:embed in db/migrations/migrations.go and run
# automatically when the binary is started with the `migrate` subcommand:
#   /api migrate
# This is invoked by fly.toml's [deploy] release_command before traffic cuts over.
#
# Final production image target size: < 25 MB
# ──────────────────────────────────────────────────────────────────────────────

# ── Stage 1: Builder ──────────────────────────────────────────────────────────
FROM golang:1.23-alpine AS builder

WORKDIR /app

# Install build-time deps:
# - ca-certificates: embedded into the binary's TLS stack for S3/Resend calls
# - tzdata: needed by time.LoadLocation for RRULE timezone expansion (B-026)
# - git: required by go mod for VCS-tagged modules
RUN apk add --no-cache ca-certificates tzdata git

# Layer-cache dependencies before copying source code.
# This layer only rebuilds when go.mod / go.sum changes — not on every code change.
COPY go.mod go.sum ./
RUN go mod download

# Copy all source (respects .dockerignore — see ./backend/.dockerignore)
COPY . .

# Build a fully static binary.
# -w -s: strip DWARF + symbol table → 30-40% smaller binary
# CGO_ENABLED=0: no libc dependency → compatible with distroless/static-debian12
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -ldflags="-w -s" -o /api ./cmd/api

# ── Stage 2: Runtime ──────────────────────────────────────────────────────────
FROM gcr.io/distroless/static-debian12 AS runner

# Copy CA certificates (needed for TLS to S3, Resend, and Fly Postgres)
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# Copy timezone database (needed for RRULE user-timezone expansion — RUN-001 §8)
COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo

# Copy compiled binary
COPY --from=builder /api /api

# Run as non-root: distroless/static-debian12 uid 65534 = nobody
# GOV-008 §7: no process runs as root in production
USER 65534

EXPOSE 8080

# Default entrypoint starts the API server.
# To run migrations: docker run <image> migrate
# On Fly.io: [deploy] release_command = "/api migrate" handles this automatically.
ENTRYPOINT ["/api"]
