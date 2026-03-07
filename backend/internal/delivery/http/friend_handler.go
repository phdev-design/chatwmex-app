package http

import (
	"net/http"

	"chatwmex_backend/internal/delivery/http/middleware"
	"chatwmex_backend/internal/domain"
	"chatwmex_backend/pkg/response"

	"github.com/gin-gonic/gin"
)

type FriendHandler struct {
	FriendUsecase domain.FriendUsecase
}

func NewFriendHandler(r *gin.Engine, fus domain.FriendUsecase, jwtSecret string) {
	handler := &FriendHandler{
		FriendUsecase: fus,
	}

	api := r.Group("/api/v1/friends")
	api.Use(middleware.AuthMiddleware(jwtSecret))
	{
		api.POST("/request", handler.SendRequest)
		api.POST("/accept/:id", handler.AcceptRequest)
		api.POST("/reject/:id", handler.RejectRequest)
		api.GET("/requests", handler.GetRequests)
		api.GET("/list", handler.GetFriends)
		api.DELETE("/unfriend/:id", handler.Unfriend)
		// Block routes
		api.POST("/block", handler.BlockUser)
		api.POST("/unblock", handler.UnblockUser)
		api.GET("/block/check", handler.CheckIsBlocked)
		api.GET("/blocks", handler.GetBlockList)
	}
}

type SendFriendRequestInput struct {
	UsernameOrEmail string `json:"username_or_email" binding:"required"`
}

func (h *FriendHandler) SendRequest(c *gin.Context) {
	var input SendFriendRequestInput
	if err := c.ShouldBindJSON(&input); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	userID := c.GetString(middleware.ContextUserIDKey)
	err := h.FriendUsecase.SendFriendRequest(c.Request.Context(), userID, input.UsernameOrEmail)
	if err != nil {
		if err.Error() == "user not found" {
			response.Error(c, http.StatusNotFound, err.Error())
			return
		}
		if err.Error() == "already friends" || err.Error() == "request already exists" {
			response.Error(c, http.StatusConflict, err.Error())
			return
		}
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}

	response.Success(c, "Friend request sent")
}

func (h *FriendHandler) AcceptRequest(c *gin.Context) {
	requestID := c.Param("id")
	err := h.FriendUsecase.AcceptFriendRequest(c.Request.Context(), requestID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, "Friend request accepted")
}

func (h *FriendHandler) RejectRequest(c *gin.Context) {
	requestID := c.Param("id")
	err := h.FriendUsecase.RejectFriendRequest(c.Request.Context(), requestID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, "Friend request rejected")
}

func (h *FriendHandler) GetRequests(c *gin.Context) {
	userID := c.GetString(middleware.ContextUserIDKey)
	requests, err := h.FriendUsecase.GetPendingRequests(c.Request.Context(), userID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, requests)
}

func (h *FriendHandler) GetFriends(c *gin.Context) {
	userID := c.GetString(middleware.ContextUserIDKey)
	friends, err := h.FriendUsecase.GetFriends(c.Request.Context(), userID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, friends)
}

func (h *FriendHandler) Unfriend(c *gin.Context) {
	targetUserID := c.Param("id") // target user's ID
	currentUserID := c.GetString(middleware.ContextUserIDKey)

	err := h.FriendUsecase.UnfriendUser(c.Request.Context(), currentUserID, targetUserID)
	if err != nil {
		if err.Error() == "not friends" {
			response.Error(c, http.StatusBadRequest, err.Error())
			return
		}
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, "Unfriended successfully")
}

func (h *FriendHandler) BlockUser(c *gin.Context) {
	var body map[string]string
	if err := c.ShouldBindJSON(&body); err != nil {
		response.Error(c, http.StatusBadRequest, "invalid request body")
		return
	}
	targetID, ok := body["target_id"]
	if !ok || targetID == "" {
		response.Error(c, http.StatusBadRequest, "target_id is required")
		return
	}

	blockerID := c.GetString(middleware.ContextUserIDKey)
	if err := h.FriendUsecase.BlockUser(c.Request.Context(), blockerID, targetID); err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, "Blocked successfully")
}

func (h *FriendHandler) UnblockUser(c *gin.Context) {
	var body map[string]string
	if err := c.ShouldBindJSON(&body); err != nil {
		response.Error(c, http.StatusBadRequest, "invalid request body")
		return
	}
	targetID, ok := body["target_id"]
	if !ok || targetID == "" {
		response.Error(c, http.StatusBadRequest, "target_id is required")
		return
	}

	blockerID := c.GetString(middleware.ContextUserIDKey)
	if err := h.FriendUsecase.UnblockUser(c.Request.Context(), blockerID, targetID); err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, "Unblocked successfully")
}

func (h *FriendHandler) CheckIsBlocked(c *gin.Context) {
	targetID := c.Query("target_id")
	if targetID == "" {
		response.Error(c, http.StatusBadRequest, "target_id is required")
		return
	}

	userID := c.GetString(middleware.ContextUserIDKey)
	isBlocked, err := h.FriendUsecase.IsBlocked(c.Request.Context(), userID, targetID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}

	response.Success(c, map[string]bool{"is_blocked": isBlocked})
}

func (h *FriendHandler) GetBlockList(c *gin.Context) {
	userID := c.GetString(middleware.ContextUserIDKey)
	users, err := h.FriendUsecase.GetBlockedUsers(c.Request.Context(), userID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, users)
}
