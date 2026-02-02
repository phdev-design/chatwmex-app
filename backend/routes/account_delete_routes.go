package routes

import (
	"net/http"

	"chatwme/backend/controllers"
	"chatwme/backend/middleware"

	"github.com/gorilla/mux"
)

// SetupAccountDeleteRoutes 設置帳號刪除相關路由
func SetupAccountDeleteRoutes(r *mux.Router) {
	// 刪除帳號 - 需要認證
	r.Handle("/account/delete", middleware.JwtAuthentication(http.HandlerFunc(controllers.DeleteAccount))).Methods("DELETE")

	// 獲取帳號刪除信息 - 需要認證
	r.Handle("/account/deletion-info", middleware.JwtAuthentication(http.HandlerFunc(controllers.GetAccountDeletionInfo))).Methods("GET")

	// 取消帳號刪除 - 需要認證
	r.Handle("/account/cancel-deletion", middleware.JwtAuthentication(http.HandlerFunc(controllers.CancelAccountDeletion))).Methods("POST")
}
