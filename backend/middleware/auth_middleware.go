package middleware

import (
	"context"
	"net/http"
	"strings"

	"chatwme/backend/utils"
)

// contextKey 是一個自訂類型，用於在 context 中安全地儲存鍵值，避免衝突
type contextKey string

// UserIDKey 是用於在請求 context 中儲存使用者 ID 的鍵
const UserIDKey contextKey = "userID"

// JwtAuthentication 是一個中介軟體，用於驗證 JWT
func JwtAuthentication(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// 從請求標頭獲取 token
		authHeader := r.Header.Get("Authorization")
		if authHeader == "" {
			http.Error(w, `{"error": "請求未包含 token"}`, http.StatusUnauthorized)
			return
		}

		// token 通常以 "Bearer <token>" 的形式出現，我們需要分離它
		splitToken := strings.Split(authHeader, " ")
		if len(splitToken) != 2 || strings.ToLower(splitToken[0]) != "bearer" {
			http.Error(w, `{"error": "Token 格式不正確"}`, http.StatusUnauthorized)
			return
		}
		tokenString := splitToken[1]

		// 驗證 token
		claims, err := utils.VerifyJWT(tokenString)
		if err != nil {
			http.Error(w, `{"error": "無效的 token"}`, http.StatusUnauthorized)
			return
		}

		// Token 驗證成功，將使用者 ID 存入請求的 context 中，以便後續的處理函式使用
		ctx := context.WithValue(r.Context(), UserIDKey, claims.UserID)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}
