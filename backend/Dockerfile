# ──────────────────────────────────────────────────────────
# Stage 1: Builder
# Go 1.22 Alpine — compiles the binary
# ──────────────────────────────────────────────────────────
FROM golang:1.23-alpine AS builder

WORKDIR /app

# Install build dependencies
RUN apk add --no-cache git ca-certificates tzdata

# Cache dependencies before copying source
COPY go.mod go.sum ./
RUN go mod download

# Copy all source
COPY . .

# Build static binary (no CGO — distroless compatible)
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -ldflags="-w -s" -o /api ./cmd/api

# ──────────────────────────────────────────────────────────
# Stage 2: Runtime (distroless — minimal attack surface)
# ──────────────────────────────────────────────────────────
FROM gcr.io/distroless/static-debian12 AS runner

# Copy timezone data and CA certs from builder
COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# Copy binary
COPY --from=builder /api /api

# Non-root user (distroless default: uid 65534 = nobody)
USER 65534

EXPOSE 8080

ENTRYPOINT ["/api"]
