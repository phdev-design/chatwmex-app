package routes

import (
	"net/http"

	"chatwme/backend/controllers"
	"chatwme/backend/middleware"

	"github.com/gorilla/mux"
)

// SetupGroupRoutes 設置群組相關路由
func SetupGroupRoutes(r *mux.Router) {
	// 創建群組 - 需要認證
	r.Handle("/groups/create", middleware.JwtAuthentication(http.HandlerFunc(controllers.CreateGroup))).Methods("POST")

	// 獲取用戶群組列表 - 需要認證
	r.Handle("/groups", middleware.JwtAuthentication(http.HandlerFunc(controllers.GetUserGroups))).Methods("GET")

	// 加入群組 - 需要認證
	r.Handle("/groups/join", middleware.JwtAuthentication(http.HandlerFunc(controllers.JoinGroup))).Methods("POST")

	// 離開群組 - 需要認證
	r.Handle("/groups/leave", middleware.JwtAuthentication(http.HandlerFunc(controllers.LeaveGroup))).Methods("POST")

	// 獲取群組成員列表 - 需要認證
	r.Handle("/groups/members", middleware.JwtAuthentication(http.HandlerFunc(controllers.GetGroupMembers))).Methods("GET")

	// 邀請用戶加入群組 - 需要認證
	r.Handle("/groups/invite", middleware.JwtAuthentication(http.HandlerFunc(controllers.InviteToGroup))).Methods("POST")

	// 獲取群組邀請列表 - 需要認證
	r.Handle("/groups/invitations", middleware.JwtAuthentication(http.HandlerFunc(controllers.GetGroupInvitations))).Methods("GET")

	// 響應群組邀請 - 需要認證
	r.Handle("/groups/invitations/respond", middleware.JwtAuthentication(http.HandlerFunc(controllers.RespondToInvitation))).Methods("POST")
}
