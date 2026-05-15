package handlers

import (
	"net/http"

	"github.com/chrisjackson92/task-nibbler/backend/internal/middleware"
	"github.com/chrisjackson92/task-nibbler/backend/internal/services"
	"github.com/gin-gonic/gin"
)

// GamificationHandler wires GamificationService to the two gamification API routes.
type GamificationHandler struct {
	gamif services.GamificationService
}

// NewGamificationHandler creates a GamificationHandler.
func NewGamificationHandler(gamif services.GamificationService) *GamificationHandler {
	return &GamificationHandler{gamif: gamif}
}

// RegisterRoutes registers gamification routes on the provided group.
// Expected group base: /api/v1/gamification
func (h *GamificationHandler) RegisterRoutes(r *gin.RouterGroup) {
	r.GET("/state", h.GetState)
	r.GET("/badges", h.GetBadges)
}

// ────────────────────────────────────────────────────────────────────────────
// GET /gamification/state
// ────────────────────────────────────────────────────────────────────────────

// GetState godoc
// @Summary      Get gamification state
// @Description  Returns full state block with computed tree_state and sprite_state.
// @Tags         gamification
// @Produce      json
// @Success      200  {object}  services.GamificationStateResponse
// @Security     BearerAuth
// @Router       /gamification/state [get]
func (h *GamificationHandler) GetState(c *gin.Context) {
	userID := middleware.MustUserID(c)

	state, err := h.gamif.GetState(c.Request.Context(), userID)
	if err != nil {
		_ = c.Error(err)
		return
	}
	c.JSON(http.StatusOK, state)
}

// ────────────────────────────────────────────────────────────────────────────
// GET /gamification/badges
// ────────────────────────────────────────────────────────────────────────────

// GetBadges godoc
// @Summary      List user badges
// @Description  Returns all 14 badges with earned status. Unearned badges have earned=false and earned_at=null.
// @Tags         gamification
// @Produce      json
// @Success      200  {object}  map[string]any
// @Security     BearerAuth
// @Router       /gamification/badges [get]
func (h *GamificationHandler) GetBadges(c *gin.Context) {
	userID := middleware.MustUserID(c)

	badges, err := h.gamif.GetBadges(c.Request.Context(), userID)
	if err != nil {
		_ = c.Error(err)
		return
	}
	if badges == nil {
		badges = []*services.BadgeListItem{}
	}
	c.JSON(http.StatusOK, gin.H{"data": badges})
}
