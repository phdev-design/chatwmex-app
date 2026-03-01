package middleware

import (
	"context"
	"log"
	"net/http"
	"strings"

	"chatwme/backend/database"
	"chatwme/backend/utils"
)

type contextKey string

const UserIDKey contextKey = "userID"

// JwtAuthentication 是一個中介軟體，用於驗證 JWT token
func JwtAuthentication(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// 對於 OPTIONS 請求，直接放行（CORS preflight）
		if r.Method == "OPTIONS" {
			next.ServeHTTP(w, r)
			return
		}

		// 獲取 Authorization header
		tokenHeader := r.Header.Get("Authorization")
		if tokenHeader == "" {
			http.Error(w, `{"error": "未提供 token"}`, http.StatusUnauthorized)
			return
		}

		// token 格式通常是 "Bearer {token}"
		splitted := strings.Split(tokenHeader, " ")
		if len(splitted) != 2 {
			http.Error(w, `{"error": "無效的 token 格式"}`, http.StatusUnauthorized)
			return
		}

		tokenString := splitted[1]

		// 驗證 token
		claims, err := utils.VerifyJWT(tokenString)
		if err != nil {
			if len(tokenString) > 10 {
				log.Printf("❌ [JwtAuthentication] Invalid Token: %v | Token prefix: %s", err, tokenString[:10])
			} else {
				log.Printf("❌ [JwtAuthentication] Invalid Token: %v | Token too short", err)
			}
			http.Error(w, `{"error": "無效的 token"}`, http.StatusUnauthorized)
			return
		}

		// Check if it's a refresh token (should not be used for access)
		// Access tokens should have issuer "chatwme-backend"
		if claims.Issuer == "chatwme-backend-refresh" {
			log.Printf("❌ [JwtAuthentication] Invalid Token Type: Refresh Token used for Access | Issuer: %s", claims.Issuer)
			http.Error(w, `{"error": "Invalid token type"}`, http.StatusUnauthorized)
			return
		}

		// 將使用者資訊存入 context
		ctx := context.WithValue(r.Context(), "user", claims)
		ctx = context.WithValue(ctx, UserIDKey, claims.UserID)
		r = r.WithContext(ctx)

		next.ServeHTTP(w, r)
	})
}

// UserFromContext 從 context 中提取使用者資訊
func UserFromContext(ctx context.Context) (*utils.Claims, bool) {
	user, ok := ctx.Value("user").(*utils.Claims)
	return user, ok
}

func WithStore(store database.Store) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			ctx := database.ContextWithStore(r.Context(), store)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}
