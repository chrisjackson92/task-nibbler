package handlers

import (
	"net/http"
	"time"

	"github.com/chrisjackson92/task-nibbler/backend/internal/apierr"
	"github.com/chrisjackson92/task-nibbler/backend/internal/middleware"
	"github.com/chrisjackson92/task-nibbler/backend/internal/repositories"
	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"
)

// UserHandler handles authenticated user-profile routes.
type UserHandler struct {
	userRepo *repositories.UserRepository
}

// NewUserHandler creates a new UserHandler.
func NewUserHandler(userRepo *repositories.UserRepository) *UserHandler {
	return &UserHandler{userRepo: userRepo}
}

// ── PATCH /users/me ──────────────────────────────────────────────────────────

type updateMeRequest struct {
	DisplayName *string `json:"display_name"` // optional
	Timezone    string  `json:"timezone" binding:"required"`
}

// UpdateMe godoc
// @Summary      Update current user profile
// @Tags         users
// @Accept       json
// @Produce      json
// @Param        body body updateMeRequest true "Profile update payload"
// @Success      200 {object} map[string]interface{}
// @Security     BearerAuth
// @Router       /users/me [patch]
func (h *UserHandler) UpdateMe(c *gin.Context) {
	userID := middleware.MustUserID(c)

	var req updateMeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(apierr.ErrBadRequest)
		return
	}

	if _, err := time.LoadLocation(req.Timezone); err != nil {
		c.Error(apierr.ErrBadRequest)
		return
	}

	user, err := h.userRepo.UpdateProfile(c.Request.Context(), userID, req.DisplayName, req.Timezone)
	if err != nil {
		c.Error(err)
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"id":           user.ID,
		"email":        user.Email,
		"display_name": user.DisplayName,
		"timezone":     user.Timezone,
		"created_at":   user.CreatedAt.Format(time.RFC3339),
	})
}

// ── POST /auth/change-password ───────────────────────────────────────────────

type changePasswordRequest struct {
	CurrentPassword string `json:"current_password" binding:"required"`
	NewPassword     string `json:"new_password"     binding:"required,min=8"`
}

// ChangePassword godoc
// @Summary      Change authenticated user's password
// @Tags         auth
// @Accept       json
// @Produce      json
// @Param        body body changePasswordRequest true "Change password payload"
// @Success      200 {object} map[string]interface{}
// @Security     BearerAuth
// @Router       /auth/change-password [post]
func (h *UserHandler) ChangePassword(c *gin.Context) {
	userID := middleware.MustUserID(c)

	var req changePasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "VALIDATION_ERROR", "message": err.Error()})
		return
	}

	// Fetch current user to verify current password.
	user, err := h.userRepo.GetByID(c.Request.Context(), userID)
	if err != nil || user == nil {
		c.Error(apierr.ErrNotFound)
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.CurrentPassword)); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "INVALID_CREDENTIALS", "message": "Current password is incorrect"})
		return
	}

	newHash, err := bcrypt.GenerateFromPassword([]byte(req.NewPassword), bcrypt.DefaultCost)
	if err != nil {
		c.Error(err)
		return
	}

	if err := h.userRepo.UpdatePasswordHash(c.Request.Context(), userID, string(newHash)); err != nil {
		c.Error(err)
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Password updated successfully"})
}
