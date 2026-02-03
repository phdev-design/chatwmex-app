package routes

import (
	"encoding/json"
	"log"
	"net/http"

	"chatwme/backend/config"
	"chatwme/backend/database"
	"chatwme/backend/middleware"

	"github.com/gorilla/handlers"
	"github.com/gorilla/mux"
)

// helloHandler 是一個簡單的歡迎處理函式
func helloHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{
		"message": "Welcome to ChatwMeX API!",
		"version": "1.0.8", // 🔥 更新版本号
		"status":  "ready",
	})
}

// SetupRoutes 設定並返回一個新的 mux.Router
func SetupRoutes(store database.Store) http.Handler {
	r := mux.NewRouter()
	r.Use(middleware.WithStore(store))

	// 為所有 API 加上 /api/v1 前綴
	api := r.PathPrefix("/api/v1").Subrouter()

	// 設定通用的根路由
	api.HandleFunc("/", helloHandler).Methods("GET")

	// 健康檢查端點
	api.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]string{
			"status":  "healthy",
			"message": "Server is running",
		})
	}).Methods("GET")

	// 調試端點 - 列出所有路由
	api.HandleFunc("/debug/routes", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)

		routes := map[string]interface{}{
			"avatar_upload":       "/api/v1/avatar/upload",
			"avatar_delete":       "/api/v1/avatar/delete",
			"profile_avatar_post": "/api/v1/profile/avatar (POST)",
			"profile_avatar_put":  "/api/v1/profile/avatar (PUT)",
			"voice_upload":        "/api/v1/rooms/{id}/voice",
			"voice_url":           "/api/v1/rooms/voice/{messageId}/url",
			"static_files":        "/uploads/",
			"health":              "/api/v1/health",
		}

		json.NewEncoder(w).Encode(map[string]interface{}{
			"message": "Available routes",
			"routes":  routes,
		})
	}).Methods("GET")

	// 註冊來自不同模組的路由
	SetupUserRoutes(api)
	SetupChatRoomRoutes(api)
	SetupChatMessageRoutes(api)
	SetupVoiceMessageRoutes(api)  // 語音消息路由
	SetupAvatarRoutes(api)        // 🔥 新增：頭像路由
	SetupDeviceRoutes(api)        // 🔥 新增：設備信息路由
	SetupMessageDeleteRoutes(api) // 🔥 新增：消息刪除路由
	SetupAccountDeleteRoutes(api) // 🔥 新增：帳號刪除路由
	SetupGroupRoutes(api)         // 🔥 新增：群組路由
	SetupDebugRoutes(api)         // 🔥 新增：调试路由
	SetupStaticRoutes(r)          // 注意：這個要在 api 子路由之外
	SetupRefreshTokenRoutes(api)  // 🔥 新增這一行

	log.Println("Routes have been initialized")

	// 使用配置中的 CORS 設定
	cfg := config.LoadConfig()
	allowedOrigins := handlers.AllowedOrigins(cfg.AllowedOrigins)

	allowedMethods := handlers.AllowedMethods([]string{
		"GET", "POST", "PUT", "DELETE", "OPTIONS", "HEAD",
	})

	allowedHeaders := handlers.AllowedHeaders([]string{
		"Content-Type",
		"Authorization",
		"X-Requested-With",
		"Accept",
		"Origin",
		"Access-Control-Request-Method",
		"Access-Control-Request-Headers",
		"Range", // 🔥 支持音频流媒体
	})

	// 允許憑證
	allowCredentials := handlers.AllowCredentials()

	// 將 CORS 中介軟體應用到路由器
	return handlers.CORS(
		allowedOrigins,
		allowedMethods,
		allowedHeaders,
		allowCredentials,
	)(r)
}
