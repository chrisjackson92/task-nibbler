package handlers

import (
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/chrisjackson92/task-nibbler/backend/internal/apierr"
	"github.com/chrisjackson92/task-nibbler/backend/internal/middleware"
	"github.com/chrisjackson92/task-nibbler/backend/internal/repositories"
	"github.com/chrisjackson92/task-nibbler/backend/internal/services"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

// TaskHandler wires the TaskService to Gin route handlers.
type TaskHandler struct {
	tasks     services.TaskService
	recurring services.RecurringService
}

// NewTaskHandler creates a new TaskHandler.
func NewTaskHandler(tasks services.TaskService, recurring services.RecurringService) *TaskHandler {
	return &TaskHandler{tasks: tasks, recurring: recurring}
}

// RegisterRoutes registers all task routes on the given router group.
// All routes require a valid JWT (middleware.Auth must wrap the group).
func (h *TaskHandler) RegisterRoutes(r *gin.RouterGroup) {
	r.GET("", h.List)
	r.POST("", h.Create)
	r.POST("/recurring", h.CreateRecurring)
	r.GET("/:id", h.Get)
	r.PATCH("/:id", h.Update)
	r.DELETE("/:id", h.Delete)
	r.POST("/:id/complete", h.Complete)
	r.PATCH("/:id/sort-order", h.UpdateSortOrder)
}

// ────────────────────────────────────────────────────────────────────────────
// GET /api/v1/tasks
// ────────────────────────────────────────────────────────────────────────────

// List godoc
// @Summary      List tasks
// @Description  Returns a paginated list of the authenticated user's tasks.
// @Tags         tasks
// @Produce      json
// @Param        status    query     string  false  "Filter by status (PENDING|COMPLETED|CANCELLED|overdue)"
// @Param        priority  query     string  false  "Filter by priority (LOW|MEDIUM|HIGH|CRITICAL)"
// @Param        type      query     string  false  "Filter by type (ONE_TIME|RECURRING)"
// @Param        from      query     string  false  "Tasks with end_at >= from (ISO 8601)"
// @Param        to        query     string  false  "Tasks with end_at <= to (ISO 8601)"
// @Param        search    query     string  false  "Full-text search on title + description"
// @Param        sort      query     string  false  "Sort field (due_date|priority|sort_order|created_at)"
// @Param        order     query     string  false  "Sort direction (asc|desc)"
// @Param        page      query     int     false  "Page number (default 1)"
// @Param        per_page  query     int     false  "Page size (default 50, max 100)"
// @Success      200       {object}  services.TaskPageResponse
// @Security     BearerAuth
// @Router       /tasks [get]
func (h *TaskHandler) List(c *gin.Context) {
	userID := middleware.MustUserID(c)

	filter := services.ListTasksFilter{
		Sort:  c.DefaultQuery("sort", "sort_order"),
		Order: c.DefaultQuery("order", "asc"),
	}

	if v := c.Query("status"); v != "" {
		v = strings.ToUpper(v) // normalize: accept 'pending' or 'PENDING' (Finding #1)
		// "overdue" is a virtual status — the service handles it
		if v != "OVERDUE" {
			s := repositories.TaskStatus(v)
			if s != repositories.TaskStatusPending && s != repositories.TaskStatusCompleted && s != repositories.TaskStatusCancelled {
				_ = c.Error(apierr.New(422, "VALIDATION_ERROR", "invalid status value"))
				return
			}
			filter.Status = &s
		} else {
			overdue := repositories.TaskStatus("overdue")
			filter.Status = &overdue
		}
	}
	if v := c.Query("priority"); v != "" {
		v = strings.ToUpper(v) // normalize
		p := repositories.Priority(v)
		filter.Priority = &p
	}
	if v := c.Query("type"); v != "" {
		v = strings.ToUpper(v) // normalize
		t := repositories.TaskType(v)
		filter.Type = &t
	}
	if v := c.Query("from"); v != "" {
		t, err := time.Parse(time.RFC3339, v)
		if err != nil {
			c.Error(apierr.New(422, "VALIDATION_ERROR", "invalid 'from' date format, expected ISO 8601"))
			return
		}
		filter.From = &t
	}
	if v := c.Query("to"); v != "" {
		t, err := time.Parse(time.RFC3339, v)
		if err != nil {
			c.Error(apierr.New(422, "VALIDATION_ERROR", "invalid 'to' date format, expected ISO 8601"))
			return
		}
		filter.To = &t
	}
	if v := c.Query("search"); v != "" {
		filter.Search = &v
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	perPage, _ := strconv.Atoi(c.DefaultQuery("per_page", "50"))
	filter.Page = page
	filter.PerPage = perPage

	result, err := h.tasks.ListTasks(c.Request.Context(), userID, filter)
	if err != nil {
		c.Error(err)
		return
	}
	c.JSON(http.StatusOK, result)
}

// ────────────────────────────────────────────────────────────────────────────
// POST /api/v1/tasks
// ────────────────────────────────────────────────────────────────────────────

type createTaskBody struct {
	Title       string     `json:"title"       binding:"required,max=200"`
	Description *string    `json:"description"`
	Address     *string    `json:"address"`
	Priority    string     `json:"priority"    binding:"required,oneof=LOW MEDIUM HIGH CRITICAL"`
	TaskType    string     `json:"task_type"   binding:"required,oneof=ONE_TIME RECURRING"`
	SortOrder   *int       `json:"sort_order"`
	StartAt     *time.Time `json:"start_at"`
	EndAt       *time.Time `json:"end_at"`
}

// Create godoc
// @Summary      Create task (one-time)
// @Tags         tasks
// @Accept       json
// @Produce      json
// @Param        body  body      createTaskBody  true  "Task data"
// @Success      201   {object}  services.TaskResponse
// @Security     BearerAuth
// @Router       /tasks [post]
func (h *TaskHandler) Create(c *gin.Context) {
	userID := middleware.MustUserID(c)

	var body createTaskBody
	if err := c.ShouldBindJSON(&body); err != nil {
		c.Error(apierr.New(422, "VALIDATION_ERROR", err.Error()))
		return
	}

	resp, err := h.tasks.CreateTask(c.Request.Context(), userID, services.CreateTaskRequest{
		Title:       body.Title,
		Description: body.Description,
		Address:     body.Address,
		Priority:    repositories.Priority(body.Priority),
		TaskType:    repositories.TaskType(body.TaskType),
		SortOrder:   body.SortOrder,
		StartAt:     body.StartAt,
		EndAt:       body.EndAt,
	})
	if err != nil {
		c.Error(err)
		return
	}
	c.JSON(http.StatusCreated, resp)
}

// CreateRecurring godoc
// @Summary      Create a recurring task
// @Tags         tasks
// @Accept       json
// @Produce      json
// @Param        body  body      services.CreateRecurringRequest  true  "Recurring task payload with rrule"
// @Success      201   {object}  services.TaskResponse
// @Security     BearerAuth
// @Router       /tasks/recurring [post]
func (h *TaskHandler) CreateRecurring(c *gin.Context) {
	userID := middleware.MustUserID(c)

	var req services.CreateRecurringRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(apierr.New(422, "VALIDATION_ERROR", err.Error()))
		return
	}

	resp, err := h.recurring.CreateRecurring(c.Request.Context(), userID, req)
	if err != nil {
		c.Error(err)
		return
	}
	c.JSON(http.StatusCreated, resp)
}

// ────────────────────────────────────────────────────────────────────────────
// GET /api/v1/tasks/:id
// ────────────────────────────────────────────────────────────────────────────

// Get godoc
// @Summary      Get task
// @Tags         tasks
// @Produce      json
// @Param        id   path      string  true  "Task UUID"
// @Success      200  {object}  services.TaskResponse
// @Security     BearerAuth
// @Router       /tasks/{id} [get]
func (h *TaskHandler) Get(c *gin.Context) {
	userID := middleware.MustUserID(c)
	id, ok := parseUUID(c, "id")
	if !ok {
		return
	}
	resp, err := h.tasks.GetTask(c.Request.Context(), id, userID)
	if err != nil {
		c.Error(err)
		return
	}
	c.JSON(http.StatusOK, resp)
}

// ────────────────────────────────────────────────────────────────────────────
// PATCH /api/v1/tasks/:id
// ────────────────────────────────────────────────────────────────────────────

type updateTaskBody struct {
	Title       *string    `json:"title"`
	Description *string    `json:"description"`
	Address     *string    `json:"address"`
	Priority    *string    `json:"priority"`
	TaskType    *string    `json:"task_type"`
	Status      *string    `json:"status"`
	SortOrder   *int       `json:"sort_order"`
	StartAt     *time.Time `json:"start_at"`
	EndAt       *time.Time `json:"end_at"`
}

// Update godoc
// @Summary      Update task (partial)
// @Tags         tasks
// @Accept       json
// @Produce      json
// @Param        id     path      string          true   "Task UUID"
// @Param        scope  query     string          false  "Scope for recurring tasks: this_only|this_and_future"
// @Param        body   body      updateTaskBody  true   "Fields to update"
// @Success      200    {object}  services.TaskResponse
// @Security     BearerAuth
// @Router       /tasks/{id} [patch]
func (h *TaskHandler) Update(c *gin.Context) {
	userID := middleware.MustUserID(c)
	id, ok := parseUUID(c, "id")
	if !ok {
		return
	}

	var body updateTaskBody
	if err := c.ShouldBindJSON(&body); err != nil {
		c.Error(apierr.New(422, "VALIDATION_ERROR", err.Error()))
		return
	}

	scope := c.Query("scope")

	// Route to RecurringService when scope param is present
	if scope != "" {
		req := services.UpdateScopedRequest{
			Scope: scope,
		}
		// Map body to embedded UpdateTaskRequest
		req.Title = body.Title
		req.Description = body.Description
		req.Address = body.Address
		req.SortOrder = body.SortOrder
		req.StartAt = body.StartAt
		req.EndAt = body.EndAt
		if body.Priority != nil {
			p := repositories.Priority(*body.Priority)
			req.Priority = &p
		}
		if body.TaskType != nil {
			t := repositories.TaskType(*body.TaskType)
			req.TaskType = &t
		}
		if body.Status != nil {
			s := repositories.TaskStatus(*body.Status)
			req.Status = &s
		}
		resp, err := h.recurring.UpdateScoped(c.Request.Context(), id, userID, req)
		if err != nil {
			c.Error(err)
			return
		}
		c.JSON(http.StatusOK, resp)
		return
	}

	// One-time task (no scope) — original path
	req := services.UpdateTaskRequest{
		Title:       body.Title,
		Description: body.Description,
		Address:     body.Address,
		SortOrder:   body.SortOrder,
		StartAt:     body.StartAt,
		EndAt:       body.EndAt,
	}
	if body.Priority != nil {
		p := repositories.Priority(*body.Priority)
		req.Priority = &p
	}
	if body.TaskType != nil {
		t := repositories.TaskType(*body.TaskType)
		req.TaskType = &t
	}
	if body.Status != nil {
		s := repositories.TaskStatus(*body.Status)
		req.Status = &s
	}

	resp, err := h.tasks.UpdateTask(c.Request.Context(), id, userID, req)
	if err != nil {
		c.Error(err)
		return
	}
	c.JSON(http.StatusOK, resp)
}

// ────────────────────────────────────────────────────────────────────────────
// DELETE /api/v1/tasks/:id
// ────────────────────────────────────────────────────────────────────────────

// Delete godoc
// @Summary      Delete task
// @Tags         tasks
// @Param        id     path  string  true   "Task UUID"
// @Param        scope  query string  false  "Scope for recurring tasks: this_only|this_and_future"
// @Success      204
// @Security     BearerAuth
// @Router       /tasks/{id} [delete]
func (h *TaskHandler) Delete(c *gin.Context) {
	userID := middleware.MustUserID(c)
	id, ok := parseUUID(c, "id")
	if !ok {
		return
	}

	scope := c.Query("scope")
	if scope != "" {
		if err := h.recurring.DeleteScoped(c.Request.Context(), id, userID, scope); err != nil {
			c.Error(err)
			return
		}
		c.Status(http.StatusNoContent)
		return
	}

	if err := h.tasks.DeleteTask(c.Request.Context(), id, userID); err != nil {
		c.Error(err)
		return
	}
	c.Status(http.StatusNoContent)
}

// ────────────────────────────────────────────────────────────────────────────
// POST /api/v1/tasks/:id/complete
// ────────────────────────────────────────────────────────────────────────────

// Complete godoc
// @Summary      Mark task complete
// @Tags         tasks
// @Produce      json
// @Param        id  path      string  true  "Task UUID"
// @Success      200 {object}  services.CompleteTaskResponse
// @Security     BearerAuth
// @Router       /tasks/{id}/complete [post]
func (h *TaskHandler) Complete(c *gin.Context) {
	userID := middleware.MustUserID(c)
	id, ok := parseUUID(c, "id")
	if !ok {
		return
	}
	resp, err := h.tasks.CompleteTask(c.Request.Context(), id, userID)
	if err != nil {
		c.Error(err)
		return
	}
	c.JSON(http.StatusOK, resp)
}

// ────────────────────────────────────────────────────────────────────────────
// PATCH /api/v1/tasks/:id/sort-order
// ────────────────────────────────────────────────────────────────────────────

type updateSortOrderBody struct {
	SortOrder int `json:"sort_order" binding:"min=0"`
}

// UpdateSortOrder godoc
// @Summary      Update task sort order
// @Tags         tasks
// @Accept       json
// @Param        id    path  string               true  "Task UUID"
// @Param        body  body  updateSortOrderBody  true  "New sort order"
// @Success      204
// @Security     BearerAuth
// @Router       /tasks/{id}/sort-order [patch]
func (h *TaskHandler) UpdateSortOrder(c *gin.Context) {
	userID := middleware.MustUserID(c)
	id, ok := parseUUID(c, "id")
	if !ok {
		return
	}

	var body updateSortOrderBody
	if err := c.ShouldBindJSON(&body); err != nil {
		c.Error(apierr.New(422, "VALIDATION_ERROR", err.Error()))
		return
	}

	if err := h.tasks.UpdateSortOrder(c.Request.Context(), id, userID, body.SortOrder); err != nil {
		c.Error(err)
		return
	}
	c.Status(http.StatusNoContent)
}

// ────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ────────────────────────────────────────────────────────────────────────────

// parseUUID extracts and validates a UUID path param, responding 422 on failure.
func parseUUID(c *gin.Context, param string) (uuid.UUID, bool) {
	raw := c.Param(param)
	id, err := uuid.Parse(raw)
	if err != nil {
		c.Error(apierr.New(422, "VALIDATION_ERROR", param+" must be a valid UUID"))
		return uuid.UUID{}, false
	}
	return id, true
}
