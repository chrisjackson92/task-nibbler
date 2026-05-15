// Package handlers contains all HTTP handlers for the Task Nibbles API.
// Handlers parse Gin context, validate input, call services, and map results to HTTP responses.
// Handlers NEVER import pgx or db types — they only import services.
package handlers

import (
	"net/http"

	"github.com/chrisjackson92/task-nibbler/backend/internal/apierr"
	"github.com/chrisjackson92/task-nibbler/backend/internal/services"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

// AuthHandler handles all /api/v1/auth routes.
type AuthHandler struct {
	authSvc *services.AuthService
}

// NewAuthHandler creates a new AuthHandler.
func NewAuthHandler(authSvc *services.AuthService) *AuthHandler {
	return &AuthHandler{authSvc: authSvc}
}

// registerRequest is the JSON body for POST /auth/register.
type registerRequest struct {
	Email    string `json:"email"    binding:"required"`
	Password string `json:"password" binding:"required"`
	Timezone string `json:"timezone"`
}

// Register godoc
// @Summary      Register a new account
// @Description  Creates a new user, seeds gamification state, and returns JWT tokens.
// @Tags         auth
// @Accept       json
// @Produce      json
// @Param        body body registerRequest true "Registration payload"
// @Success      201 {object} map[string]interface{}
// @Failure      409 {object} map[string]interface{} "EMAIL_ALREADY_EXISTS"
// @Failure      422 {object} map[string]interface{} "VALIDATION_ERROR"
// @Router       /auth/register [post]
func (h *AuthHandler) Register(c *gin.Context) {
	var req registerRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(apierr.ErrBadRequest)
		return
	}

	result, err := h.authSvc.Register(c.Request.Context(), services.RegisterInput{
		Email:    req.Email,
		Password: req.Password,
		Timezone: req.Timezone,
	})
	if err != nil {
		c.Error(err)
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"user": gin.H{
			"id":         result.User.ID,
			"email":      result.User.Email,
			"timezone":   result.User.Timezone,
			"created_at": result.User.CreatedAt,
		},
		"access_token":  result.AccessToken,
		"refresh_token": result.RefreshToken,
	})
}

// loginRequest is the JSON body for POST /auth/login.
type loginRequest struct {
	Email    string `json:"email"    binding:"required"`
	Password string `json:"password" binding:"required"`
}

// Login godoc
// @Summary      Authenticate a user
// @Description  Validates credentials and returns JWT access + refresh tokens.
// @Tags         auth
// @Accept       json
// @Produce      json
// @Param        body body loginRequest true "Login payload"
// @Success      200 {object} map[string]interface{}
// @Failure      401 {object} map[string]interface{} "UNAUTHORIZED"
// @Router       /auth/login [post]
func (h *AuthHandler) Login(c *gin.Context) {
	var req loginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(apierr.ErrBadRequest)
		return
	}

	result, err := h.authSvc.Login(c.Request.Context(), services.LoginInput{
		Email:    req.Email,
		Password: req.Password,
	})
	if err != nil {
		c.Error(err)
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"user": gin.H{
			"id":         result.User.ID,
			"email":      result.User.Email,
			"timezone":   result.User.Timezone,
			"created_at": result.User.CreatedAt,
		},
		"access_token":  result.AccessToken,
		"refresh_token": result.RefreshToken,
	})
}

// refreshRequest is the JSON body for POST /auth/refresh.
type refreshRequest struct {
	RefreshToken string `json:"refresh_token" binding:"required"`
}

// Refresh godoc
// @Summary      Rotate refresh token
// @Description  Validates the refresh token, revokes it, and issues a new pair.
// @Tags         auth
// @Accept       json
// @Produce      json
// @Param        body body refreshRequest true "Refresh payload"
// @Success      200 {object} map[string]interface{}
// @Failure      401 {object} map[string]interface{} "REFRESH_TOKEN_EXPIRED or REFRESH_TOKEN_REVOKED"
// @Router       /auth/refresh [post]
func (h *AuthHandler) Refresh(c *gin.Context) {
	var req refreshRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(apierr.ErrBadRequest)
		return
	}

	result, err := h.authSvc.Refresh(c.Request.Context(), req.RefreshToken)
	if err != nil {
		c.Error(err)
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"access_token":  result.AccessToken,
		"refresh_token": result.RefreshToken,
	})
}

// logoutRequest is the JSON body for DELETE /auth/logout.
type logoutRequest struct {
	RefreshToken string `json:"refresh_token" binding:"required"`
}

// Logout godoc
// @Summary      Revoke refresh token
// @Description  Revokes the given refresh token. Returns 204 No Content.
// @Tags         auth
// @Security     BearerAuth
// @Accept       json
// @Param        body body logoutRequest true "Logout payload"
// @Success      204
// @Router       /auth/logout [delete]
func (h *AuthHandler) Logout(c *gin.Context) {
	var req logoutRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(apierr.ErrBadRequest)
		return
	}

	if err := h.authSvc.Logout(c.Request.Context(), req.RefreshToken); err != nil {
		c.Error(err)
		return
	}

	c.Status(http.StatusNoContent)
}

// forgotPasswordRequest is the JSON body for POST /auth/forgot-password.
type forgotPasswordRequest struct {
	Email string `json:"email" binding:"required"`
}

// ForgotPassword godoc
// @Summary      Request password reset
// @Description  Sends a reset email if the address exists. Always returns 200 (email enumeration prevention).
// @Tags         auth
// @Accept       json
// @Produce      json
// @Param        body body forgotPasswordRequest true "Forgot password payload"
// @Success      200 {object} map[string]interface{}
// @Router       /auth/forgot-password [post]
func (h *AuthHandler) ForgotPassword(c *gin.Context) {
	var req forgotPasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		// Note: even parse errors return 200 per spec (prevent enumeration via error shape)
		c.JSON(http.StatusOK, gin.H{
			"message": "If that email address is registered, a reset link has been sent.",
		})
		return
	}

	// Fire-and-forget — never returns errors to the caller
	go h.authSvc.ForgotPassword(c.Request.Context(), req.Email)

	c.JSON(http.StatusOK, gin.H{
		"message": "If that email address is registered, a reset link has been sent.",
	})
}

// resetPasswordRequest is the JSON body for POST /auth/reset-password.
type resetPasswordRequest struct {
	Token       string `json:"token"        binding:"required"`
	NewPassword string `json:"new_password" binding:"required"`
}

// ResetPassword godoc
// @Summary      Set new password
// @Description  Validates the reset token and sets a new password.
// @Tags         auth
// @Accept       json
// @Produce      json
// @Param        body body resetPasswordRequest true "Reset password payload"
// @Success      204
// @Failure      401 {object} map[string]interface{} "TOKEN_INVALID"
// @Failure      422 {object} map[string]interface{} "VALIDATION_ERROR"
// @Router       /auth/reset-password [post]
func (h *AuthHandler) ResetPassword(c *gin.Context) {
	var req resetPasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(apierr.ErrBadRequest)
		return
	}

	if err := h.authSvc.ResetPassword(c.Request.Context(), req.Token, req.NewPassword); err != nil {
		c.Error(err)
		return
	}

	c.Status(http.StatusNoContent)
}

// DeleteAccount godoc
// @Summary      Delete user account
// @Description  Permanently deletes the authenticated user and all associated data.
// @Tags         auth
// @Security     BearerAuth
// @Success      204
// @Router       /auth/account [delete]
func (h *AuthHandler) DeleteAccount(c *gin.Context) {
	userID := c.MustGet("user_id").(uuid.UUID)

	if err := h.authSvc.DeleteAccount(c.Request.Context(), userID); err != nil {
		c.Error(err)
		return
	}

	c.Status(http.StatusNoContent)
}
