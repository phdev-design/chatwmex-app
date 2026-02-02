package routes

import (
	"net/http"

	"chatwme/backend/controllers"
	"chatwme/backend/middleware"

	"github.com/gorilla/mux"
)

// SetupMessageDeleteRoutes 設置消息刪除相關路由
func SetupMessageDeleteRoutes(r *mux.Router) {
	// 刪除消息 - 需要認證
	r.Handle("/messages/delete", middleware.JwtAuthentication(http.HandlerFunc(controllers.DeleteMessage))).Methods("DELETE")

	// 恢復消息 - 需要認證
	r.Handle("/messages/restore", middleware.JwtAuthentication(http.HandlerFunc(controllers.RestoreMessage))).Methods("POST")

	// 獲取已刪除消息列表 - 需要認證
	r.Handle("/messages/deleted", middleware.JwtAuthentication(http.HandlerFunc(controllers.GetDeletedMessages))).Methods("GET")
}
