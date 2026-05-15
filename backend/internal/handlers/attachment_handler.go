package handlers

import (
	"net/http"

	"github.com/chrisjackson92/task-nibbler/backend/internal/apierr"
	"github.com/chrisjackson92/task-nibbler/backend/internal/middleware"
	"github.com/chrisjackson92/task-nibbler/backend/internal/services"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

// AttachmentHandler wires AttachmentService to Gin routes.
// Routes are registered as a sub-group of /tasks/:id/attachments.
type AttachmentHandler struct {
	attachments services.AttachmentService
}

// NewAttachmentHandler creates a new AttachmentHandler.
func NewAttachmentHandler(attachments services.AttachmentService) *AttachmentHandler {
	return &AttachmentHandler{attachments: attachments}
}

// RegisterRoutes registers attachment sub-routes on the provided router group.
// Expected group base: /api/v1/tasks/:id/attachments
func (h *AttachmentHandler) RegisterRoutes(r *gin.RouterGroup) {
	r.POST("", h.PreRegister)
	r.POST("/:aid/confirm", h.Confirm)
	r.GET("", h.List)
	r.GET("/:aid/url", h.GetDownloadURL)
	r.DELETE("/:aid", h.Delete)
}

// ────────────────────────────────────────────────────────────────────────────
// POST /tasks/:id/attachments
// ────────────────────────────────────────────────────────────────────────────

// PreRegister godoc
// @Summary      Pre-register attachment
// @Description  Initiates Pattern A upload. Returns presigned S3 PUT URL.
// @Tags         attachments
// @Accept       json
// @Produce      json
// @Param        id      path  string                        true  "Task ID"
// @Param        body    body  services.PreRegisterRequest   true  "Pre-register body"
// @Success      201     {object}  services.PreRegisterResponse
// @Security     BearerAuth
// @Router       /tasks/{id}/attachments [post]
func (h *AttachmentHandler) PreRegister(c *gin.Context) {
	userID := middleware.MustUserID(c)

	taskID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		_ = c.Error(apierr.ErrTaskNotFound)
		return
	}

	var req services.PreRegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		_ = c.Error(apierr.New(422, "VALIDATION_ERROR", err.Error()))
		return
	}

	resp, err := h.attachments.PreRegister(c.Request.Context(), taskID, userID, req)
	if err != nil {
		_ = c.Error(err)
		return
	}
	c.JSON(http.StatusCreated, resp)
}

// ────────────────────────────────────────────────────────────────────────────
// POST /tasks/:id/attachments/:aid/confirm
// ────────────────────────────────────────────────────────────────────────────

// Confirm godoc
// @Summary      Confirm upload complete
// @Description  Sets attachment status to COMPLETE after client finishes S3 PUT.
// @Tags         attachments
// @Param        id   path  string  true  "Task ID"
// @Param        aid  path  string  true  "Attachment ID"
// @Success      204
// @Security     BearerAuth
// @Router       /tasks/{id}/attachments/{aid}/confirm [post]
func (h *AttachmentHandler) Confirm(c *gin.Context) {
	userID := middleware.MustUserID(c)

	aid, err := uuid.Parse(c.Param("aid"))
	if err != nil {
		_ = c.Error(apierr.ErrAttachmentNotFound)
		return
	}

	if err := h.attachments.Confirm(c.Request.Context(), aid, userID); err != nil {
		_ = c.Error(err)
		return
	}
	c.Status(http.StatusNoContent)
}

// ────────────────────────────────────────────────────────────────────────────
// GET /tasks/:id/attachments
// ────────────────────────────────────────────────────────────────────────────

// List godoc
// @Summary      List attachments
// @Description  Returns COMPLETE attachments for a task.
// @Tags         attachments
// @Produce      json
// @Param        id  path  string  true  "Task ID"
// @Success      200  {object}  map[string]any
// @Security     BearerAuth
// @Router       /tasks/{id}/attachments [get]
func (h *AttachmentHandler) List(c *gin.Context) {
	userID := middleware.MustUserID(c)

	taskID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		_ = c.Error(apierr.ErrTaskNotFound)
		return
	}

	attachments, err := h.attachments.List(c.Request.Context(), taskID, userID)
	if err != nil {
		_ = c.Error(err)
		return
	}
	if attachments == nil {
		attachments = []*services.AttachmentResponse{}
	}
	c.JSON(http.StatusOK, gin.H{"data": attachments})
}

// ────────────────────────────────────────────────────────────────────────────
// GET /tasks/:id/attachments/:aid/url
// ────────────────────────────────────────────────────────────────────────────

// GetDownloadURL godoc
// @Summary      Get download URL
// @Description  Returns a fresh presigned S3 GET URL (TTL 60 min). Do not cache.
// @Tags         attachments
// @Produce      json
// @Param        id   path  string  true  "Task ID"
// @Param        aid  path  string  true  "Attachment ID"
// @Success      200  {object}  services.DownloadURLResponse
// @Security     BearerAuth
// @Router       /tasks/{id}/attachments/{aid}/url [get]
func (h *AttachmentHandler) GetDownloadURL(c *gin.Context) {
	userID := middleware.MustUserID(c)

	aid, err := uuid.Parse(c.Param("aid"))
	if err != nil {
		_ = c.Error(apierr.ErrAttachmentNotFound)
		return
	}

	resp, err := h.attachments.GetDownloadURL(c.Request.Context(), aid, userID)
	if err != nil {
		_ = c.Error(err)
		return
	}
	c.JSON(http.StatusOK, resp)
}

// ────────────────────────────────────────────────────────────────────────────
// DELETE /tasks/:id/attachments/:aid
// ────────────────────────────────────────────────────────────────────────────

// Delete godoc
// @Summary      Delete attachment
// @Description  Deletes S3 object synchronously, then deletes DB row.
// @Tags         attachments
// @Param        id   path  string  true  "Task ID"
// @Param        aid  path  string  true  "Attachment ID"
// @Success      204
// @Security     BearerAuth
// @Router       /tasks/{id}/attachments/{aid} [delete]
func (h *AttachmentHandler) Delete(c *gin.Context) {
	userID := middleware.MustUserID(c)

	aid, err := uuid.Parse(c.Param("aid"))
	if err != nil {
		_ = c.Error(apierr.ErrAttachmentNotFound)
		return
	}

	if err := h.attachments.Delete(c.Request.Context(), aid, userID); err != nil {
		_ = c.Error(err)
		return
	}
	c.Status(http.StatusNoContent)
}
