package routes

import (
	"chatwme/backend/controllers"
	"chatwme/backend/middleware"
	"github.com/gorilla/mux"
)

// SetupChatMessageRoutes 設定所有與聊天訊息相關的路由
func SetupChatMessageRoutes(router *mux.Router) {
	// 建立一個子路由器，並為其應用 JWT 驗證中介軟體
	// 這樣，所有在這個子路由器下定義的路由都需要先通過驗證
	messageRouter := router.PathPrefix("/messages").Subrouter()
	messageRouter.Use(middleware.JwtAuthentication)

	// 將路由註冊到新的子路由器上
	// 現在 GET /api/v1/messages/{room} 會受到保護
	messageRouter.HandleFunc("/{room}", controllers.GetMessagesByRoom).Methods("GET")
	
	// 注意：聊天室的消息路由現在移到了 chat_room_routes.go 中
	// 作為 /api/v1/rooms/{id}/messages
}