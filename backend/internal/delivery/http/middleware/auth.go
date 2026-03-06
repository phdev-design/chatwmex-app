package middleware

import (
	"net/http"
	"strings"

	"chatwmex_backend/pkg/response"
	"chatwmex_backend/pkg/token"

	"github.com/gin-gonic/gin"
)

const (
	AuthorizationHeaderKey  = "Authorization"
	AuthorizationTypeBearer = "Bearer"
	ContextUserIDKey        = "userID"
)

// AuthMiddleware creates a gin middleware for JWT authentication.
func AuthMiddleware(jwtSecret string) gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader(AuthorizationHeaderKey)
		if len(authHeader) == 0 {
			response.Error(c, http.StatusUnauthorized, "Authorization header is missing")
			c.Abort()
			return
		}

		fields := strings.Fields(authHeader)
		if len(fields) != 2 {
			response.Error(c, http.StatusUnauthorized, "Invalid authorization header format")
			c.Abort()
			return
		}

		authType := fields[0]
		if authType != AuthorizationTypeBearer {
			response.Error(c, http.StatusUnauthorized, "Unsupported authorization type")
			c.Abort()
			return
		}

		tokenString := fields[1]
		validatedToken, err := token.ValidateToken(tokenString, jwtSecret)
		if err != nil || !validatedToken.Valid {
			response.Error(c, http.StatusUnauthorized, "Invalid or expired token")
			c.Abort()
			return
		}

		claims, ok := validatedToken.Claims.(*token.JWTClaims)
		if !ok {
			response.Error(c, http.StatusUnauthorized, "Invalid token claims")
			c.Abort()
			return
		}

		c.Set(ContextUserIDKey, claims.UserID)
		c.Next()
	}
}
