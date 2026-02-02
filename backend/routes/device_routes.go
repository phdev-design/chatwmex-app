package routes

import (
	"net/http"

	"chatwme/backend/controllers"
	"chatwme/backend/middleware"

	"github.com/gorilla/mux"
)

// SetupDeviceRoutes 設置設備相關路由
func SetupDeviceRoutes(r *mux.Router) {
	// 獲取用戶設備列表 - 需要認證
	r.Handle("/devices", middleware.JwtAuthentication(http.HandlerFunc(controllers.GetUserDevices))).Methods("GET")

	// 獲取用戶登入會話 - 需要認證
	r.Handle("/sessions", middleware.JwtAuthentication(http.HandlerFunc(controllers.GetUserSessions))).Methods("GET")

	// 獲取當前會話信息 - 需要認證
	r.Handle("/sessions/current", middleware.JwtAuthentication(http.HandlerFunc(controllers.GetCurrentSession))).Methods("GET")

	// 終止指定會話 - 需要認證
	r.Handle("/sessions/terminate", middleware.JwtAuthentication(http.HandlerFunc(controllers.TerminateSession))).Methods("POST")
}
