package routes

import (
	"chatwme/backend/controllers"
	"chatwme/backend/middleware"
	"github.com/gorilla/mux"
)

// SetupBlockRoutes sets up routes for blocking/unblocking users
func SetupBlockRoutes(router *mux.Router) {
	// Create a subrouter for user-related block operations
	// We attach to /users to keep the API clean: /api/v1/users/...
	userRouter := router.PathPrefix("/users").Subrouter()
	userRouter.Use(middleware.JwtAuthentication)

	// Define specific routes first to avoid matching {id} wildcard
	
	// Get list of blocked users
	// GET /api/v1/users/blocked
	userRouter.HandleFunc("/blocked", controllers.GetBlockedUsers).Methods("GET")

	// Block a user
	// POST /api/v1/users/{id}/block
	userRouter.HandleFunc("/{id}/block", controllers.BlockUser).Methods("POST")

	// Unblock a user
	// POST /api/v1/users/{id}/unblock
	userRouter.HandleFunc("/{id}/unblock", controllers.UnblockUser).Methods("POST")
}
