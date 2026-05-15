package middleware

import (
	"log/slog"
	"net/http"
	"time"

	"github.com/chrisjackson92/task-nibbler/backend/internal/apierr"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

// ErrorResponse is the JSON envelope shape for all error responses (CON-001 §5).
type ErrorResponse struct {
	Error ErrorBody `json:"error"`
}

// ErrorBody is the inner error object.
type ErrorBody struct {
	Code      string              `json:"code"`
	Message   string              `json:"message"`
	RequestID string              `json:"request_id"`
	Details   map[string][]string `json:"details"`
}

// Recovery is the top-level middleware that:
//  1. Assigns a unique request_id UUID to every request
//  2. Catches panics and returns a structured 500 response
//  3. Converts apierr.APIError values into the CON-001 §5 envelope
func Recovery() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Assign request ID
		requestID := uuid.New().String()
		c.Set("request_id", requestID)
		c.Header("Request-Id", requestID)

		defer func() {
			if r := recover(); r != nil {
				slog.Error("panic recovered",
					"request_id", requestID,
					"panic", r,
					"path", c.Request.URL.Path,
				)
				c.AbortWithStatusJSON(http.StatusInternalServerError, ErrorResponse{
					Error: ErrorBody{
						Code:      apierr.ErrInternalServer.Code,
						Message:   apierr.ErrInternalServer.Message,
						RequestID: requestID,
					},
				})
			}
		}()

		c.Next()

		// After handler executes — check for apierr errors set via c.Error()
		if len(c.Errors) > 0 {
			last := c.Errors.Last()
			requestID, _ := c.Get("request_id")
			rid, _ := requestID.(string)

			// Check for ValidationError (has per-field details)
			if valErr, ok := last.Err.(*apierr.ValidationError); ok {
				c.JSON(valErr.Status, ErrorResponse{
					Error: ErrorBody{
						Code:      valErr.Code,
						Message:   valErr.Message,
						RequestID: rid,
						Details:   valErr.Details,
					},
				})
				return
			}

			// Check for typed APIError
			if apiErr, ok := last.Err.(*apierr.APIError); ok {
				c.JSON(apiErr.Status, ErrorResponse{
					Error: ErrorBody{
						Code:      apiErr.Code,
						Message:   apiErr.Message,
						RequestID: rid,
					},
				})
				return
			}

			// Unknown error — return 500
			slog.Error("unhandled error",
				"request_id", rid,
				"error", last.Err.Error(),
			)
			c.JSON(http.StatusInternalServerError, ErrorResponse{
				Error: ErrorBody{
					Code:      apierr.ErrInternalServer.Code,
					Message:   apierr.ErrInternalServer.Message,
					RequestID: rid,
				},
			})
		}
	}
}

// Logger logs every request with structured fields.
func Logger() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		path := c.Request.URL.Path

		c.Next()

		duration := time.Since(start)
		requestID, _ := c.Get("request_id")
		rid, _ := requestID.(string)

		slog.Info("request",
			"request_id", rid,
			"method", c.Request.Method,
			"path", path,
			"status", c.Writer.Status(),
			"duration_ms", duration.Milliseconds(),
			"client_ip", c.ClientIP(),
		)
	}
}

// CORS adds permissive CORS headers suitable for mobile + local dev.
// In production the Flutter app uses a native HTTP client — CORS is a non-issue,
// but we include it for potential web tooling and Swagger UI.
func CORS() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Header("Access-Control-Allow-Origin", "*")
		c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Origin, Authorization, Content-Type")

		if c.Request.Method == http.MethodOptions {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}
		c.Next()
	}
}
