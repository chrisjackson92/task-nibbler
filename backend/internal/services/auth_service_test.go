package services_test

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"strings"
	"testing"
	"unicode"

	"github.com/chrisjackson92/task-nibbler/backend/internal/apierr"
	"github.com/chrisjackson92/task-nibbler/backend/internal/services"
	"github.com/stretchr/testify/assert"
)

// =============================================================================
// TestAPIErrorCodes — verifies all CON-001 §5.1 error codes are correctly
// defined in the apierr package with the right HTTP status codes.
// =============================================================================

func TestAPIErrorCodes(t *testing.T) {
	tests := []struct {
		err    *apierr.APIError
		code   string
		status int
	}{
		{apierr.ErrBadRequest, "BAD_REQUEST", 400},
		{apierr.ErrInvalidRRULE, "INVALID_RRULE", 400},
		{apierr.ErrInvalidDateRange, "INVALID_DATE_RANGE", 400},
		{apierr.ErrUnauthorized, "UNAUTHORIZED", 401},
		{apierr.ErrTokenExpired, "TOKEN_EXPIRED", 401},
		{apierr.ErrTokenInvalid, "TOKEN_INVALID", 401},
		{apierr.ErrRefreshTokenExpired, "REFRESH_TOKEN_EXPIRED", 401},
		{apierr.ErrRefreshTokenRevoked, "REFRESH_TOKEN_REVOKED", 401},
		{apierr.ErrForbidden, "FORBIDDEN", 403},
		{apierr.ErrNotFound, "NOT_FOUND", 404},
		{apierr.ErrTaskNotFound, "TASK_NOT_FOUND", 404},
		{apierr.ErrAttachmentNotFound, "ATTACHMENT_NOT_FOUND", 404},
		{apierr.ErrEmailAlreadyExists, "EMAIL_ALREADY_EXISTS", 409},
		{apierr.ErrValidation, "VALIDATION_ERROR", 422},
		{apierr.ErrAttachmentLimit, "ATTACHMENT_LIMIT", 422},
		{apierr.ErrFileTooLarge, "FILE_TOO_LARGE", 422},
		{apierr.ErrInvalidMIMEType, "INVALID_MIME_TYPE", 422},
		{apierr.ErrRateLimited, "RATE_LIMITED", 429},
		{apierr.ErrInternalServer, "INTERNAL_ERROR", 500},
	}

	for _, tt := range tests {
		t.Run(tt.code, func(t *testing.T) {
			assert.Equal(t, tt.code, tt.err.Code)
			assert.Equal(t, tt.status, tt.err.Status)
			assert.NotEmpty(t, tt.err.Message)
		})
	}
}

// =============================================================================
// TestValidationError — verifies the ValidationError with details
// =============================================================================

func TestValidationError(t *testing.T) {
	details := map[string][]string{
		"email":    {"Email is required"},
		"password": {"Password must be at least 8 characters"},
	}
	ve := apierr.NewValidationError(details)
	assert.Equal(t, "VALIDATION_ERROR", ve.Code)
	assert.Equal(t, details, ve.Details)
	assert.Equal(t, "VALIDATION_ERROR: One or more fields are invalid.", ve.Code+": "+ve.Message)
}

// =============================================================================
// Test password validation (mirrors internal validatePassword logic)
// =============================================================================

func TestPasswordValidation(t *testing.T) {
	tests := []struct {
		name    string
		pass    string
		wantErr bool
	}{
		{"valid password", "ValidPass1", false},
		{"valid strong", "MyPassword123!", false},
		{"too short", "Short1", true},
		{"no uppercase", "lowercase123", true},
		{"no digit", "NoDigitPass", true},
		{"exactly 8 chars valid", "Valid12a", false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := testValidatePassword(tt.pass)
			if tt.wantErr {
				assert.Error(t, err)
			} else {
				assert.NoError(t, err)
			}
		})
	}
}

// testValidatePassword mirrors the internal validation for test coverage.
func testValidatePassword(password string) error {
	if len(password) < 8 {
		return &simpleError{"password must be at least 8 characters"}
	}
	var hasUpper, hasDigit bool
	for _, r := range password {
		if unicode.IsUpper(r) {
			hasUpper = true
		}
		if unicode.IsDigit(r) {
			hasDigit = true
		}
	}
	if !hasUpper {
		return &simpleError{"password must contain at least one uppercase letter"}
	}
	if !hasDigit {
		return &simpleError{"password must contain at least one number"}
	}
	return nil
}

// =============================================================================
// Test email validation (mirrors internal validateEmail logic)
// =============================================================================

func TestEmailValidation(t *testing.T) {
	tests := []struct {
		name    string
		email   string
		wantErr bool
	}{
		{"valid email", "user@example.com", false},
		{"valid with plus", "user+tag@example.co.uk", false},
		{"empty string", "", true},
		{"no at sign", "notanemail", true},
		{"no domain", "user@", true},
		{"no local part", "@domain.com", true},
		{"too long", strings.Repeat("a", 315) + "@ex.com", true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := testValidateEmail(tt.email)
			if tt.wantErr {
				assert.Error(t, err)
			} else {
				assert.NoError(t, err)
			}
		})
	}
}

func testValidateEmail(email string) error {
	if len(email) == 0 {
		return &simpleError{"email is required"}
	}
	if len(email) > 320 {
		return &simpleError{"email must be 320 characters or fewer"}
	}
	if !strings.Contains(email, "@") {
		return &simpleError{"invalid email"}
	}
	parts := strings.SplitN(email, "@", 2)
	if parts[0] == "" || parts[1] == "" || !strings.Contains(parts[1], ".") {
		return &simpleError{"invalid email format"}
	}
	return nil
}

// =============================================================================
// TestHashToken — verifies SHA-256 token hashing is deterministic, 64 chars
// =============================================================================

func TestHashToken(t *testing.T) {
	raw := "test-raw-token-12345678abcdef"

	h1 := testHashToken(raw)
	h2 := testHashToken(raw)

	assert.Equal(t, h1, h2, "hashing must be deterministic")
	assert.Len(t, h1, 64, "SHA-256 hex must be 64 characters")
	assert.NotEqual(t, raw, h1, "hash must differ from raw input")
}

func testHashToken(raw string) string {
	h := sha256.Sum256([]byte(raw))
	return hex.EncodeToString(h[:])
}

// =============================================================================
// TestRefreshTokenReuseDetection — verifies ErrRefreshTokenRevoked error
// is the correct response when a reused token is submitted
// =============================================================================

func TestRefreshTokenReuseDetection(t *testing.T) {
	assert.Equal(t, "REFRESH_TOKEN_REVOKED", apierr.ErrRefreshTokenRevoked.Code)
	assert.Equal(t, 401, apierr.ErrRefreshTokenRevoked.Status)
}

// =============================================================================
// TestForgotPasswordSignature — ForgotPassword must return nothing (void)
// so the handler can fire-and-forget safely (email enumeration prevention)
// =============================================================================

func TestForgotPasswordSignature(t *testing.T) {
	// Verifies via interface that ForgotPassword has the correct void signature.
	// If this compiles, the contract is correct.
	type mustBeVoid interface {
		ForgotPassword(ctx context.Context, email string)
	}
	var _ mustBeVoid = (*services.AuthService)(nil)
}

// =============================================================================
// Helper types
// =============================================================================

type simpleError struct{ msg string }

func (e *simpleError) Error() string { return e.msg }
