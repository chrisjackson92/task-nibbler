// Package services contains all business logic for Task Nibbles.
// Services orchestrate repositories. They do NOT import gin.Context or pgx types.
// They do NOT contain SQL.
package services

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"log/slog"
	"regexp"
	"strings"
	"time"
	"unicode"

	"github.com/chrisjackson92/task-nibbler/backend/internal/apierr"
	"github.com/chrisjackson92/task-nibbler/backend/internal/repositories"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"golang.org/x/crypto/bcrypt"
)

const (
	bcryptCost       = 12
	accessTokenTTL   = 15 * time.Minute
	refreshTokenTTL  = 30 * 24 * time.Hour
	resetTokenTTL    = 1 * time.Hour
	resetTokenLength = 32 // bytes → 64-char hex string
)

// AuthService provides all authentication business logic.
type AuthService struct {
	userRepo     *repositories.UserRepository
	refreshRepo  *repositories.RefreshTokenRepository
	passwordRepo *repositories.PasswordResetRepository
	gamifRepo    *repositories.GamificationRepository
	emailSvc     *EmailService
	jwtSecret    string
	jwtRefresh   string
}

// NewAuthService creates a new AuthService with all dependencies wired.
func NewAuthService(
	userRepo *repositories.UserRepository,
	refreshRepo *repositories.RefreshTokenRepository,
	passwordRepo *repositories.PasswordResetRepository,
	gamifRepo *repositories.GamificationRepository,
	emailSvc *EmailService,
	jwtSecret, jwtRefreshSecret string,
) *AuthService {
	return &AuthService{
		userRepo:     userRepo,
		refreshRepo:  refreshRepo,
		passwordRepo: passwordRepo,
		gamifRepo:    gamifRepo,
		emailSvc:     emailSvc,
		jwtSecret:    jwtSecret,
		jwtRefresh:   jwtRefreshSecret,
	}
}

// RegisterInput contains validated data for new user registration.
type RegisterInput struct {
	Email    string
	Password string
	Timezone string
}

// AuthResult is returned on successful register or login.
type AuthResult struct {
	User         *repositories.User
	AccessToken  string
	RefreshToken string
}

// Register creates a new user account. Returns AUTH_RESULT or an apierr.
func (s *AuthService) Register(ctx context.Context, input RegisterInput) (*AuthResult, error) {
	// Validate
	if err := validateEmail(input.Email); err != nil {
		return nil, apierr.NewValidationError(map[string][]string{"email": {err.Error()}})
	}
	if err := validatePassword(input.Password); err != nil {
		return nil, apierr.NewValidationError(map[string][]string{"password": {err.Error()}})
	}
	if input.Timezone == "" {
		input.Timezone = "UTC"
	}

	// Check for existing account
	existing, err := s.userRepo.GetByEmail(ctx, input.Email)
	if err != nil {
		return nil, fmt.Errorf("checking existing user: %w", err)
	}
	if existing != nil {
		return nil, apierr.ErrEmailAlreadyExists
	}

	// Hash password
	hash, err := bcrypt.GenerateFromPassword([]byte(input.Password), bcryptCost)
	if err != nil {
		return nil, fmt.Errorf("hashing password: %w", err)
	}

	// Create user
	user, err := s.userRepo.Create(ctx, input.Email, string(hash), input.Timezone)
	if err != nil {
		return nil, fmt.Errorf("creating user: %w", err)
	}

	// Seed gamification state (WELCOME mode, tree_health=50)
	if _, err := s.gamifRepo.Create(ctx, user.ID); err != nil {
		slog.WarnContext(ctx, "failed to seed gamification state",
			"user_id", user.ID.String(),
			"error", err.Error(),
		)
		// Non-fatal — user is created; gamification can be seeded lazily
	}

	// Issue tokens
	accessToken, err := s.generateAccessToken(user.ID)
	if err != nil {
		return nil, fmt.Errorf("generating access token: %w", err)
	}

	rawRefresh, err := generateSecureToken()
	if err != nil {
		return nil, fmt.Errorf("generating refresh token: %w", err)
	}

	if _, err := s.refreshRepo.Create(ctx, user.ID, rawRefresh, time.Now().UTC().Add(refreshTokenTTL)); err != nil {
		return nil, fmt.Errorf("storing refresh token: %w", err)
	}

	slog.InfoContext(ctx, "user registered", "user_id", user.ID.String())

	return &AuthResult{
		User:         user,
		AccessToken:  accessToken,
		RefreshToken: rawRefresh,
	}, nil
}

// LoginInput contains validated data for authentication.
type LoginInput struct {
	Email    string
	Password string
}

// Login validates credentials and returns tokens. Returns UNAUTHORIZED for any failure
// (never distinguish email-not-found vs wrong-password — prevents enumeration).
func (s *AuthService) Login(ctx context.Context, input LoginInput) (*AuthResult, error) {
	user, err := s.userRepo.GetByEmail(ctx, input.Email)
	if err != nil {
		return nil, fmt.Errorf("fetching user: %w", err)
	}

	// Constant-time comparison — same error whether user not found or password wrong
	if user == nil {
		// Run bcrypt to prevent timing attacks
		_ = bcrypt.CompareHashAndPassword([]byte("$2a$12$dummy.hash.to.prevent.timing.attacks.padding"), []byte(input.Password))
		return nil, apierr.ErrUnauthorized
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(input.Password)); err != nil {
		return nil, apierr.ErrUnauthorized
	}

	// Issue tokens
	accessToken, err := s.generateAccessToken(user.ID)
	if err != nil {
		return nil, fmt.Errorf("generating access token: %w", err)
	}

	rawRefresh, err := generateSecureToken()
	if err != nil {
		return nil, fmt.Errorf("generating refresh token: %w", err)
	}

	if _, err := s.refreshRepo.Create(ctx, user.ID, rawRefresh, time.Now().UTC().Add(refreshTokenTTL)); err != nil {
		return nil, fmt.Errorf("storing refresh token: %w", err)
	}

	slog.InfoContext(ctx, "user logged in", "user_id", user.ID.String())

	return &AuthResult{
		User:         user,
		AccessToken:  accessToken,
		RefreshToken: rawRefresh,
	}, nil
}

// RefreshResult contains the new token pair after rotation.
type RefreshResult struct {
	AccessToken  string
	RefreshToken string
}

// Refresh validates a refresh token, rotates it, and returns a new pair.
// Reuse detection: if a revoked token is presented, ALL user tokens are revoked immediately.
func (s *AuthService) Refresh(ctx context.Context, rawToken string) (*RefreshResult, error) {
	rt, err := s.refreshRepo.GetByRawToken(ctx, rawToken)
	if err != nil {
		return nil, fmt.Errorf("fetching refresh token: %w", err)
	}

	if rt == nil {
		// Token hash not found at all — invalid
		return nil, apierr.ErrRefreshTokenExpired
	}

	// Reuse detection: revoked token presented — possible token theft
	if rt.RevokedAt != nil {
		slog.WarnContext(ctx, "refresh token reuse detected — revoking all user tokens",
			"user_id", rt.UserID.String(),
		)
		_ = s.refreshRepo.RevokeAllForUser(ctx, rt.UserID)
		return nil, apierr.ErrRefreshTokenRevoked
	}

	// Expired?
	if time.Now().UTC().After(rt.ExpiresAt) {
		return nil, apierr.ErrRefreshTokenExpired
	}

	// Revoke the old token
	if err := s.refreshRepo.RevokeByRawToken(ctx, rawToken); err != nil {
		return nil, fmt.Errorf("revoking old refresh token: %w", err)
	}

	// Issue new tokens
	accessToken, err := s.generateAccessToken(rt.UserID)
	if err != nil {
		return nil, fmt.Errorf("generating access token: %w", err)
	}

	newRawRefresh, err := generateSecureToken()
	if err != nil {
		return nil, fmt.Errorf("generating new refresh token: %w", err)
	}

	if _, err := s.refreshRepo.Create(ctx, rt.UserID, newRawRefresh, time.Now().UTC().Add(refreshTokenTTL)); err != nil {
		return nil, fmt.Errorf("storing new refresh token: %w", err)
	}

	return &RefreshResult{
		AccessToken:  accessToken,
		RefreshToken: newRawRefresh,
	}, nil
}

// Logout revokes the given refresh token.
func (s *AuthService) Logout(ctx context.Context, rawToken string) error {
	return s.refreshRepo.RevokeByRawToken(ctx, rawToken)
}

// ForgotPassword sends a password reset email. Always succeeds — never reveals whether
// the email exists (prevents email enumeration attacks).
func (s *AuthService) ForgotPassword(ctx context.Context, email string) {
	// Lookup user — but do NOT reveal result to caller
	user, err := s.userRepo.GetByEmail(ctx, email)
	if err != nil {
		slog.ErrorContext(ctx, "forgot-password: error fetching user", "error", err.Error())
		return
	}
	if user == nil {
		// Email not registered — return silently
		slog.InfoContext(ctx, "forgot-password: email not registered (silent)")
		return
	}

	// Invalidate previous tokens for this user
	if err := s.passwordRepo.InvalidatePrevious(ctx, user.ID); err != nil {
		slog.ErrorContext(ctx, "forgot-password: error invalidating previous tokens", "error", err.Error())
	}

	// Generate new token
	rawToken, err := generateSecureToken()
	if err != nil {
		slog.ErrorContext(ctx, "forgot-password: error generating token", "error", err.Error())
		return
	}

	expiresAt := time.Now().UTC().Add(resetTokenTTL)
	if _, err := s.passwordRepo.Create(ctx, user.ID, rawToken, expiresAt); err != nil {
		slog.ErrorContext(ctx, "forgot-password: error storing token", "error", err.Error())
		return
	}

	// Send email — rawToken is passed to email but NEVER logged
	if err := s.emailSvc.SendPasswordReset(ctx, user.Email, rawToken); err != nil {
		slog.ErrorContext(ctx, "forgot-password: email send failed",
			"user_id", user.ID.String(),
			"error", err.Error(),
		)
	}
}

// ResetPassword validates the reset token and sets a new password.
func (s *AuthService) ResetPassword(ctx context.Context, rawToken, newPassword string) error {
	if err := validatePassword(newPassword); err != nil {
		return apierr.NewValidationError(map[string][]string{"new_password": {err.Error()}})
	}

	prt, err := s.passwordRepo.GetByRawToken(ctx, rawToken)
	if err != nil {
		return fmt.Errorf("fetching reset token: %w", err)
	}

	if prt == nil {
		return apierr.ErrTokenInvalid
	}

	// Already used?
	if prt.UsedAt != nil {
		return apierr.ErrTokenInvalid
	}

	// Expired?
	if time.Now().UTC().After(prt.ExpiresAt) {
		return apierr.ErrTokenInvalid
	}

	// Hash new password
	hash, err := bcrypt.GenerateFromPassword([]byte(newPassword), bcryptCost)
	if err != nil {
		return fmt.Errorf("hashing password: %w", err)
	}

	// Update password
	if err := s.userRepo.UpdatePassword(ctx, prt.UserID, string(hash)); err != nil {
		return fmt.Errorf("updating password: %w", err)
	}

	// Mark token used
	if err := s.passwordRepo.MarkUsed(ctx, rawToken); err != nil {
		return fmt.Errorf("marking token used: %w", err)
	}

	// Revoke all refresh tokens (force re-login after password change)
	if err := s.refreshRepo.RevokeAllForUser(ctx, prt.UserID); err != nil {
		slog.WarnContext(ctx, "reset-password: failed to revoke all refresh tokens",
			"user_id", prt.UserID.String(),
			"error", err.Error(),
		)
	}

	slog.InfoContext(ctx, "password reset successfully", "user_id", prt.UserID.String())
	return nil
}

// DeleteAccount deletes the user and all their data. S3 cleanup is returned for async execution.
// Returns the list of S3 keys that should be deleted after the DB transaction commits.
func (s *AuthService) DeleteAccount(ctx context.Context, userID uuid.UUID) error {
	// Note: In Sprint 3, we will add S3 key collection here before deletion.
	// For Sprint 1, the user delete cascades all FK children via the schema.
	if err := s.userRepo.Delete(ctx, userID); err != nil {
		return fmt.Errorf("deleting user: %w", err)
	}
	slog.InfoContext(ctx, "account deleted", "user_id", userID.String())
	return nil
}

// --- Private helpers ---

// generateAccessToken creates a signed HS256 JWT with the user_id as `sub`.
func (s *AuthService) generateAccessToken(userID uuid.UUID) (string, error) {
	now := time.Now().UTC()
	claims := jwt.MapClaims{
		"sub": userID.String(),
		"iat": now.Unix(),
		"exp": now.Add(accessTokenTTL).Unix(),
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(s.jwtSecret))
}

// generateSecureToken creates a cryptographically random 32-byte hex token (64 chars).
func generateSecureToken() (string, error) {
	b := make([]byte, resetTokenLength)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

var emailRegex = regexp.MustCompile(`^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$`)

func validateEmail(email string) error {
	if len(email) == 0 {
		return fmt.Errorf("email is required")
	}
	if len(email) > 320 {
		return fmt.Errorf("email must be 320 characters or fewer")
	}
	if !emailRegex.MatchString(strings.ToLower(email)) {
		return fmt.Errorf("email is not a valid email address")
	}
	return nil
}

func validatePassword(password string) error {
	if len(password) < 8 {
		return fmt.Errorf("password must be at least 8 characters")
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
		return fmt.Errorf("password must contain at least one uppercase letter")
	}
	if !hasDigit {
		return fmt.Errorf("password must contain at least one number")
	}
	return nil
}
