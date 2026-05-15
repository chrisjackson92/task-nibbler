package handlers

import (
	"net/http"

	"github.com/chrisjackson92/task-nibbler/backend/internal/apierr"
	"github.com/chrisjackson92/task-nibbler/backend/internal/services"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

// RecurringHandler routes recurring-specific task operations.
// One-time task CRUD is handled by TaskHandler; this handler handles only
// the recurring-flavoured variants of PATCH and DELETE (scope parameter).
type RecurringHandler struct {
	svc services.RecurringService
}

// NewRecurringHandler creates a RecurringHandler.
func NewRecurringHandler(svc services.RecurringService) *RecurringHandler {
	return &RecurringHandler{svc: svc}
}

// RegisterRoutes mounts the recurring endpoints on the provided router group.
// The group is expected to be mounted at /api/v1/tasks (shared with TaskHandler).
// Only the single POST /tasks route for RECURRING creation is added here.
// PATCH and DELETE routes are handled by TaskHandler, which delegates to RecurringService
// when task_type=RECURRING and scope is present.
func (h *RecurringHandler) RegisterRoutes(r *gin.RouterGroup) {
	// POST /api/v1/tasks/recurring — creates a recurring task + rule
	r.POST("/recurring", h.CreateRecurring)
}

// CreateRecurring godoc
// @Summary      Create a recurring task
// @Description  Creates a recurring_rule + first concrete task instance. Body must include a valid RRULE string.
// @Tags         tasks
// @Accept       json
// @Produce      json
// @Param        body body services.CreateRecurringRequest true "Recurring task payload"
// @Success      201 {object} services.TaskResponse
// @Failure      422 {object} apierr.APIError
// @Router       /tasks/recurring [post]
func (h *RecurringHandler) CreateRecurring(c *gin.Context) {
	userID := c.MustGet("user_id").(uuid.UUID)

	var req services.CreateRecurringRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(apierr.New(422, "VALIDATION_ERROR", err.Error()))
		return
	}

	resp, err := h.svc.CreateRecurring(c.Request.Context(), userID, req)
	if err != nil {
		c.Error(err)
		return
	}

	c.JSON(http.StatusCreated, resp)
}
