package apierr

import "net/http"

// New creates an ad-hoc APIError with the given HTTP status, machine-readable code, and message.
// Use pre-defined sentinel errors where possible; use New for dynamic messages (e.g. validation details).
func New(status int, code, message string) *APIError {
	return &APIError{Status: status, Code: code, Message: message}
}


// APIError represents a typed application error with an HTTP status code and machine-readable code.
// Satisfies the error interface so handlers can use c.Error(apierr.ErrTaskNotFound).
type APIError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
	Status  int    `json:"-"`
}

func (e *APIError) Error() string {
	return e.Message
}

// Standard API errors — full list from CON-001 §5.1.
var (
	// 400
	ErrBadRequest      = &APIError{Code: "BAD_REQUEST", Message: "Malformed JSON or missing required field.", Status: http.StatusBadRequest}
	ErrInvalidRRULE    = &APIError{Code: "INVALID_RRULE", Message: "Recurring rule string is not a valid iCal RRULE.", Status: http.StatusBadRequest}
	ErrInvalidDateRange = &APIError{Code: "INVALID_DATE_RANGE", Message: "end_at must be after start_at.", Status: http.StatusBadRequest}

	// 401
	ErrUnauthorized          = &APIError{Code: "UNAUTHORIZED", Message: "Authentication required.", Status: http.StatusUnauthorized}
	ErrTokenExpired          = &APIError{Code: "TOKEN_EXPIRED", Message: "Access token has expired. Please refresh your session.", Status: http.StatusUnauthorized}
	ErrTokenInvalid          = &APIError{Code: "TOKEN_INVALID", Message: "Token signature is invalid or tampered.", Status: http.StatusUnauthorized}
	ErrRefreshTokenExpired   = &APIError{Code: "REFRESH_TOKEN_EXPIRED", Message: "Refresh token has expired. Please log in again.", Status: http.StatusUnauthorized}
	ErrRefreshTokenRevoked   = &APIError{Code: "REFRESH_TOKEN_REVOKED", Message: "Refresh token was revoked. Please log in again.", Status: http.StatusUnauthorized}

	// 403
	ErrForbidden = &APIError{Code: "FORBIDDEN", Message: "You do not have permission to access this resource.", Status: http.StatusForbidden}

	// 404
	ErrNotFound           = &APIError{Code: "NOT_FOUND", Message: "The requested resource was not found.", Status: http.StatusNotFound}
	ErrTaskNotFound       = &APIError{Code: "TASK_NOT_FOUND", Message: "The requested task does not exist or you do not have access to it.", Status: http.StatusNotFound}
	ErrAttachmentNotFound = &APIError{Code: "ATTACHMENT_NOT_FOUND", Message: "The requested attachment was not found.", Status: http.StatusNotFound}
	ErrUserNotFound       = &APIError{Code: "USER_NOT_FOUND", Message: "User not found.", Status: http.StatusNotFound}

	// 409
	ErrEmailAlreadyExists = &APIError{Code: "EMAIL_ALREADY_EXISTS", Message: "An account with that email address already exists.", Status: http.StatusConflict}

	// 422
	ErrValidation          = &APIError{Code: "VALIDATION_ERROR", Message: "One or more fields are invalid.", Status: http.StatusUnprocessableEntity}
	ErrAttachmentLimit     = &APIError{Code: "ATTACHMENT_LIMIT", Message: "This task already has the maximum number of attachments (10).", Status: http.StatusUnprocessableEntity}
	ErrFileTooLarge        = &APIError{Code: "FILE_TOO_LARGE", Message: "Declared file size exceeds the 200 MB limit.", Status: http.StatusUnprocessableEntity}
	ErrInvalidMIMEType     = &APIError{Code: "INVALID_MIME_TYPE", Message: "The provided MIME type is not in the allowed list.", Status: http.StatusUnprocessableEntity}
	ErrAttachmentNotPending = &APIError{Code: "ATTACHMENT_NOT_PENDING", Message: "Confirm can only be called on a PENDING attachment.", Status: http.StatusUnprocessableEntity}

	// 429
	ErrRateLimited = &APIError{Code: "RATE_LIMITED", Message: "Too many requests. Please wait before retrying.", Status: http.StatusTooManyRequests}

	// 500
	ErrInternalServer = &APIError{Code: "INTERNAL_ERROR", Message: "An unexpected server error occurred.", Status: http.StatusInternalServerError}
)

// ValidationError is a special 422 error that includes per-field detail messages.
type ValidationError struct {
	*APIError
	Details map[string][]string `json:"details"`
}

// NewValidationError creates a VALIDATION_ERROR with per-field messages.
func NewValidationError(details map[string][]string) *ValidationError {
	return &ValidationError{
		APIError: ErrValidation,
		Details:  details,
	}
}

func (e *ValidationError) Error() string {
	return e.Message
}
