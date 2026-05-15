package middleware

import (
	"fmt"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/chrisjackson92/task-nibbler/backend/internal/apierr"
	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

// MustUserID extracts the authenticated user's UUID from the Gin context.
// Panics if the auth middleware was not applied — this is intentional; it is
// a programming error, not a runtime error.
func MustUserID(c *gin.Context) uuid.UUID {
	return c.MustGet("user_id").(uuid.UUID)
}



// Auth validates the JWT access token and injects user_id into the Gin context.
// Protected routes must use this middleware. Handlers extract the user ID with:
//
//	userID := c.MustGet("user_id").(uuid.UUID)
func Auth(jwtSecret string) gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			c.Error(apierr.ErrUnauthorized)
			c.Abort()
			return
		}

		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) != 2 || strings.ToLower(parts[0]) != "bearer" {
			c.Error(apierr.ErrUnauthorized)
			c.Abort()
			return
		}

		tokenString := parts[1]

		token, err := jwt.Parse(tokenString, func(token *jwt.Token) (interface{}, error) {
			if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
				return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
			}
			return []byte(jwtSecret), nil
		}, jwt.WithValidMethods([]string{"HS256"}))

		if err != nil {
			requestID, _ := c.Get("request_id")
			rid, _ := requestID.(string)
			slog.Debug("JWT validation failed",
				"request_id", rid,
				"error", err.Error(),
			)

			// Distinguish expired from invalid
			if strings.Contains(err.Error(), "token is expired") {
				c.Error(apierr.ErrTokenExpired)
			} else {
				c.Error(apierr.ErrTokenInvalid)
			}
			c.Abort()
			return
		}

		claims, ok := token.Claims.(jwt.MapClaims)
		if !ok || !token.Valid {
			c.Error(apierr.ErrTokenInvalid)
			c.Abort()
			return
		}

		subRaw, ok := claims["sub"]
		if !ok {
			c.Error(apierr.ErrTokenInvalid)
			c.Abort()
			return
		}

		subStr, ok := subRaw.(string)
		if !ok {
			c.Error(apierr.ErrTokenInvalid)
			c.Abort()
			return
		}

		userID, err := uuid.Parse(subStr)
		if err != nil {
			c.Error(apierr.ErrTokenInvalid)
			c.Abort()
			return
		}

		c.Set("user_id", userID)
		c.Next()
	}
}

// RateLimit implements a token-bucket rate limiter per IP address.
// Limit is expressed as maxRequests per window duration.
// Returns 429 Too Many Requests with Retry-After header when exceeded.
func RateLimit(maxRequests int, window time.Duration) gin.HandlerFunc {
	type bucket struct {
		tokens   float64
		lastSeen time.Time
	}

	// Per-IP bucket store (in-memory, sufficient for MVP single-process)
	buckets := make(map[string]*bucket)
	refillRate := float64(maxRequests) / window.Seconds()

	return func(c *gin.Context) {
		ip := c.ClientIP()

		b, exists := buckets[ip]
		now := time.Now()

		if !exists {
			buckets[ip] = &bucket{tokens: float64(maxRequests) - 1, lastSeen: now}
			c.Next()
			return
		}

		// Refill tokens based on elapsed time
		elapsed := now.Sub(b.lastSeen).Seconds()
		b.tokens += elapsed * refillRate
		if b.tokens > float64(maxRequests) {
			b.tokens = float64(maxRequests)
		}
		b.lastSeen = now

		if b.tokens < 1 {
			// Calculate retry-after seconds
			retryAfter := int((1 - b.tokens) / refillRate)
			if retryAfter < 1 {
				retryAfter = 1
			}

			requestID, _ := c.Get("request_id")
			rid, _ := requestID.(string)

			c.Header("X-RateLimit-Limit", fmt.Sprintf("%d", maxRequests))
			c.Header("X-RateLimit-Remaining", "0")
			c.Header("X-RateLimit-Reset", fmt.Sprintf("%d", now.Add(time.Duration(retryAfter)*time.Second).Unix()))
			c.Header("Retry-After", fmt.Sprintf("%d", retryAfter))

			c.AbortWithStatusJSON(http.StatusTooManyRequests, map[string]interface{}{
				"error": map[string]interface{}{
					"code":       apierr.ErrRateLimited.Code,
					"message":    fmt.Sprintf("Too many requests. Please wait %d seconds before retrying.", retryAfter),
					"request_id": rid,
					"details":    nil,
				},
			})
			return
		}

		b.tokens--

		// Add rate limit info headers on all responses
		c.Header("X-RateLimit-Limit", fmt.Sprintf("%d", maxRequests))
		c.Header("X-RateLimit-Remaining", fmt.Sprintf("%d", int(b.tokens)))

		c.Next()
	}
}
