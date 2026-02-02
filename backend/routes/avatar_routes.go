package routes

import (
	"net/http"

	"chatwme/backend/controllers"
	"chatwme/backend/middleware"

	"github.com/gorilla/mux"
)

// SetupAvatarRoutes 設置頭像相關路由
func SetupAvatarRoutes(r *mux.Router) {
	// 頭像上傳路由 - 需要認證
	r.Handle("/avatar/upload", middleware.JwtAuthentication(http.HandlerFunc(controllers.UploadAvatar))).Methods("POST")

	// 頭像刪除路由 - 需要認證
	r.Handle("/avatar/delete", middleware.JwtAuthentication(http.HandlerFunc(controllers.DeleteAvatar))).Methods("DELETE")

	// 🔥 新增：前端期望的路由 - profile/avatar
	r.Handle("/profile/avatar", middleware.JwtAuthentication(http.HandlerFunc(controllers.UploadAvatar))).Methods("POST")
	r.Handle("/profile/avatar", middleware.JwtAuthentication(http.HandlerFunc(controllers.UploadAvatar))).Methods("PUT")

	// 調試端點 - 測試頭像路由是否可達
	r.HandleFunc("/avatar/test", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"message": "Avatar routes are working", "status": "ok"}`))
	}).Methods("GET")

	// 🔥 新增：profile 路由測試端點
	r.HandleFunc("/profile/test", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"message": "Profile routes are working", "status": "ok"}`))
	}).Methods("GET")
}
