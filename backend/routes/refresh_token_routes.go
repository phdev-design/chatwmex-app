package routes

import (
	"chatwme/backend/controllers"
	"github.com/gorilla/mux"
)

// SetupRefreshTokenRoutes 設置 Token 刷新相關路由
func SetupRefreshTokenRoutes(r *mux.Router) {
	// Token 刷新端點 - 不需要認證
	r.HandleFunc("/refresh-token", controllers.RefreshToken).Methods("POST")
	
	// Token 驗證端點 - 不需要認證（可選）
	r.HandleFunc("/validate-refresh-token", controllers.ValidateRefreshToken).Methods("POST")
}