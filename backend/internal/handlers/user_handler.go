package handlers

import (
	"net/http"
	"time"

	"github.com/chrisjackson92/task-nibbler/backend/internal/apierr"
	"github.com/chrisjackson92/task-nibbler/backend/internal/middleware"
	"github.com/chrisjackson92/task-nibbler/backend/internal/repositories"
	"github.com/gin-gonic/gin"
)

// UserHandler handles authenticated user-profile routes.
type UserHandler struct {
	userRepo *repositories.UserRepository
}

// NewUserHandler creates a new UserHandler.
func NewUserHandler(userRepo *repositories.UserRepository) *UserHandler {
	return &UserHandler{userRepo: userRepo}
}

// updateMeRequest is the JSON body for PATCH /api/v1/users/me.
// Only timezone is editable for now; extend as needed.
type updateMeRequest struct {
	Timezone string `json:"timezone" binding:"required"`
}

// UpdateMe godoc
// @Summary      Update current user profile
// @Description  Updates the authenticated user's timezone. Returns the updated user object.
// @Tags         users
// @Accept       json
// @Produce      json
// @Param        body body updateMeRequest true "Profile update payload"
// @Success      200 {object} map[string]interface{}
// @Failure      400 {object} map[string]interface{} "VALIDATION_ERROR"
// @Failure      401 {object} map[string]interface{} "UNAUTHORIZED"
// @Router       /users/me [patch]
func (h *UserHandler) UpdateMe(c *gin.Context) {
	userID := middleware.MustUserID(c)

	var req updateMeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(apierr.ErrBadRequest)
		return
	}

	// Validate timezone — time.LoadLocation rejects unknown IANA names.
	if _, err := time.LoadLocation(req.Timezone); err != nil {
		c.Error(apierr.ErrBadRequest)
		return
	}

	user, err := h.userRepo.UpdateTimezone(c.Request.Context(), userID, req.Timezone)
	if err != nil {
		c.Error(err)
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"id":         user.ID,
		"email":      user.Email,
		"timezone":   user.Timezone,
		"created_at": user.CreatedAt.Format(time.RFC3339),
	})
}
