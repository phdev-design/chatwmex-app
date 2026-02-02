package routes

import (
	"chatwme/backend/controllers"
	"chatwme/backend/middleware"
	"github.com/gorilla/mux"
)

// SetupChatRoomRoutes 設定所有與聊天室相關的路由
func SetupChatRoomRoutes(router *mux.Router) {
	// 建立一個子路由器，並為其應用 JWT 驗證中介軟體
	roomRouter := router.PathPrefix("/rooms").Subrouter()
	roomRouter.Use(middleware.JwtAuthentication)

	// 聊天室管理路由
	roomRouter.HandleFunc("", controllers.GetChatRooms).Methods("GET")              // 獲取聊天室列表
	roomRouter.HandleFunc("", controllers.CreateChatRoom).Methods("POST")           // 創建聊天室
	roomRouter.HandleFunc("/{id}", controllers.GetRoomDetails).Methods("GET")       // 獲取聊天室詳情
	roomRouter.HandleFunc("/{id}/invite", controllers.InviteToRoom).Methods("POST") // 邀請用戶
	roomRouter.HandleFunc("/{id}/leave", controllers.LeaveRoom).Methods("POST")     // 離開聊天室
	roomRouter.HandleFunc("/{id}/read", controllers.MarkAsRead).Methods("POST")     // 標記已讀

	// 聊天室消息路由
	roomRouter.HandleFunc("/{id}/messages", controllers.GetMessagesByRoom).Methods("GET") // 獲取聊天記錄
	roomRouter.HandleFunc("/{id}/messages", controllers.SendMessage).Methods("POST")      // 發送消息
	
	// 語音消息路由 - 修正路由路徑
	roomRouter.HandleFunc("/{id}/voice", controllers.UploadVoiceMessage).Methods("POST")           // 上傳語音消息
	roomRouter.HandleFunc("/voice/{messageId}/url", controllers.GetVoiceMessageURL).Methods("GET") // 獲取語音消息URL
}