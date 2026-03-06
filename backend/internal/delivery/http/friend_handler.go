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
