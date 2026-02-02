package routes

import (
	"chatwme/backend/controllers"
	"chatwme/backend/middleware"
	"github.com/gorilla/mux"
)

// SetupDebugRoutes 设置调试路由
func SetupDebugRoutes(router *mux.Router) {
	// 创建调试子路由器
	debugRouter := router.PathPrefix("/debug").Subrouter()
	debugRouter.Use(middleware.JwtAuthentication)

	// 系统信息调试
	debugRouter.HandleFunc("/system", controllers.DebugSystemInfo).Methods("GET")
	
	// 语音消息调试
	debugRouter.HandleFunc("/voice/list", controllers.DebugListVoiceMessages).Methods("GET")
	debugRouter.HandleFunc("/voice/{messageId}", controllers.DebugVoiceMessageDetailed).Methods("GET")
}