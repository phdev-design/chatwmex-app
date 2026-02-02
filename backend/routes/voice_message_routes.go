package routes

import (
	"encoding/json"
	"net/http"
	"time"
	
	"chatwme/backend/controllers"
	"chatwme/backend/middleware"
	"github.com/gorilla/mux"
)

// SetupVoiceMessageRoutes 設定所有與語音消息相關的路由
func SetupVoiceMessageRoutes(router *mux.Router) {
	// 建立語音消息子路由器，並應用 JWT 驗證中介軟體
	voiceRouter := router.PathPrefix("/voice").Subrouter()
	voiceRouter.Use(middleware.JwtAuthentication)

	// 🔥 修正：語音消息路由 - 配合前端API調用
	voiceRouter.HandleFunc("/{messageId}/url", controllers.GetVoiceMessageURL).Methods("GET")   // 獲取語音消息播放URL
	voiceRouter.HandleFunc("/{messageId}/debug", controllers.DebugVoiceMessage).Methods("GET") // 调试端点
	
	// 🔥 新增：語音服務狀態檢查端點
	voiceRouter.HandleFunc("/status", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"status": "ok",
			"service": "voice",
			"timestamp": time.Now().Format(time.RFC3339),
		})
	}).Methods("GET")
}