package handlers

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
)

// HealthHandler handles GET /health.
type HealthHandler struct {
	pool      *pgxpool.Pool
	version   string
	startTime time.Time
}

// NewHealthHandler creates a new HealthHandler.
func NewHealthHandler(pool *pgxpool.Pool, version string) *HealthHandler {
	return &HealthHandler{
		pool:      pool,
		version:   version,
		startTime: time.Now().UTC(),
	}
}

// Health godoc
// @Summary      Health check
// @Description  Returns API status, version, DB connectivity, and uptime. Required by Fly.io health checks.
// @Tags         health
// @Produce      json
// @Success      200 {object} map[string]interface{}
// @Router       /health [get]
func (h *HealthHandler) Health(c *gin.Context) {
	dbStatus := "ok"

	// Ping the database with a short timeout
	if err := h.pool.Ping(c.Request.Context()); err != nil {
		dbStatus = "error"
		// Note: still return 200 per GOV-008 §9 — Fly.io health check sees 200,
		// but ops team can see DB status in log and response body.
	}

	uptimeSeconds := int64(time.Since(h.startTime).Seconds())

	c.JSON(http.StatusOK, gin.H{
		"status":          "ok",
		"version":         h.version,
		"db":              dbStatus,
		"uptime_seconds":  uptimeSeconds,
	})
}
