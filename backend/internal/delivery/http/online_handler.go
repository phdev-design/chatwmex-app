package http

import (
	"net/http"

	"chatwmex_backend/internal/delivery/http/middleware"
	"chatwmex_backend/internal/domain"
	"chatwmex_backend/pkg/response"

	"github.com/gin-gonic/gin"
)

type OnlineHandler struct {
	OnlineRepo domain.OnlineRepository
}

func NewOnlineHandler(r *gin.Engine, repo domain.OnlineRepository, authMiddleware gin.HandlerFunc) {
	handler := &OnlineHandler{OnlineRepo: repo}

	api := r.Group("/api/v1/online")
	api.Use(authMiddleware)
	{
		// 原有：只回傳 bool map
		api.POST("/check", handler.CheckOnlineStatus)
		// 新增：回傳 is_online + last_seen
		api.POST("/presence", handler.GetPresence)
	}
}

type CheckOnlineStatusRequest struct {
	UserIDs []string `json:"user_ids" binding:"required"`
}

func (h *OnlineHandler) CheckOnlineStatus(c *gin.Context) {
	_, exists := c.Get(middleware.ContextUserIDKey)
	if !exists {
		response.Error(c, http.StatusUnauthorized, "User ID not found in context")
		return
	}

	var req CheckOnlineStatusRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	if len(req.UserIDs) == 0 {
		response.Success(c, map[string]bool{})
		return
	}

	ctx := c.Request.Context()
	statusMap, err := h.OnlineRepo.GetOnlineUsers(ctx, req.UserIDs)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}

	response.Success(c, statusMap)
}

// GetPresence returns is_online + last_seen for a list of users.
func (h *OnlineHandler) GetPresence(c *gin.Context) {
	_, exists := c.Get(middleware.ContextUserIDKey)
	if !exists {
		response.Error(c, http.StatusUnauthorized, "User ID not found in context")
		return
	}

	var req CheckOnlineStatusRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	if len(req.UserIDs) == 0 {
		response.Success(c, map[string]*domain.PresenceInfo{})
		return
	}

	ctx := c.Request.Context()
	presenceMap, err := h.OnlineRepo.GetUsersPresence(ctx, req.UserIDs)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}

	response.Success(c, presenceMap)
}
