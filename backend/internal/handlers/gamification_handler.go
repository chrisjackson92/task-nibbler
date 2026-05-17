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
	r.PATCH("/companion", h.UpdateCompanion)
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

// ────────────────────────────────────────────────────────────────────────────
// PATCH /gamification/companion
// ────────────────────────────────────────────────────────────────────────────

type updateCompanionRequest struct {
	SpriteType string `json:"sprite_type" binding:"required,oneof=sprite_a sprite_b"`
	TreeType   string `json:"tree_type"   binding:"required,oneof=tree_a tree_b"`
}

// UpdateCompanion godoc
// @Summary      Update companion selection
// @Description  Persists the user's sprite and tree selection.
// @Tags         gamification
// @Accept       json
// @Produce      json
// @Param        body body updateCompanionRequest true "Companion selection"
// @Success      200  {object}  services.GamificationStateResponse
// @Security     BearerAuth
// @Router       /gamification/companion [patch]
func (h *GamificationHandler) UpdateCompanion(c *gin.Context) {
	userID := middleware.MustUserID(c)

	var req updateCompanionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "VALIDATION_ERROR", "message": err.Error()})
		return
	}

	state, err := h.gamif.UpdateCompanion(c.Request.Context(), userID, req.SpriteType, req.TreeType)
	if err != nil {
		_ = c.Error(err)
		return
	}
	c.JSON(http.StatusOK, state)
}
