package http

import (
	"net/http"

	"chatwmex_backend/internal/delivery/http/middleware"
	"chatwmex_backend/internal/domain"
	"chatwmex_backend/pkg/response"

	"github.com/gin-gonic/gin"
)

type RoomHandler struct {
	RoomUsecase domain.RoomUsecase
}

func NewRoomHandler(r *gin.Engine, ru domain.RoomUsecase, authMiddleware gin.HandlerFunc) {
	handler := &RoomHandler{
		RoomUsecase: ru,
	}

	api := r.Group("/api/v1/rooms")
	api.Use(authMiddleware)
	{
		api.POST("", handler.CreateRoom)
		api.POST("/:id/join", handler.JoinRoom)
		api.POST("/:id/leave", handler.LeaveRoom)
		api.GET("/my", handler.GetUserRooms)
		api.GET("/:id/members", handler.GetRoomMembers)
	}
}

type CreateRoomRequest struct {
	Name string `json:"name" binding:"required"`
}

func (h *RoomHandler) CreateRoom(c *gin.Context) {
	userID, exists := c.Get(middleware.ContextUserIDKey)
	if !exists {
		response.Error(c, http.StatusUnauthorized, "User ID not found in context")
		return
	}

	var req CreateRoomRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	ownerID, ok := userID.(string)
	if !ok {
		response.Error(c, http.StatusInternalServerError, "Invalid user ID type")
		return
	}

	ctx := c.Request.Context()
	room, err := h.RoomUsecase.CreateRoom(ctx, req.Name, ownerID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}

	response.Success(c, room)
}

func (h *RoomHandler) JoinRoom(c *gin.Context) {
	userID, exists := c.Get(middleware.ContextUserIDKey)
	if !exists {
		response.Error(c, http.StatusUnauthorized, "User ID not found in context")
		return
	}

	roomID := c.Param("id")
	if roomID == "" {
		response.Error(c, http.StatusBadRequest, "Room ID is required")
		return
	}

	memberID, ok := userID.(string)
	if !ok {
		response.Error(c, http.StatusInternalServerError, "Invalid user ID type")
		return
	}

	ctx := c.Request.Context()
	err := h.RoomUsecase.JoinRoom(ctx, roomID, memberID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}

	response.Success(c, "Joined room successfully")
}

func (h *RoomHandler) LeaveRoom(c *gin.Context) {
	userID, exists := c.Get(middleware.ContextUserIDKey)
	if !exists {
		response.Error(c, http.StatusUnauthorized, "User ID not found in context")
		return
	}

	roomID := c.Param("id")
	if roomID == "" {
		response.Error(c, http.StatusBadRequest, "Room ID is required")
		return
	}

	memberID, ok := userID.(string)
	if !ok {
		response.Error(c, http.StatusInternalServerError, "Invalid user ID type")
		return
	}

	ctx := c.Request.Context()
	err := h.RoomUsecase.LeaveRoom(ctx, roomID, memberID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}

	response.Success(c, "Left room successfully")
}

func (h *RoomHandler) GetUserRooms(c *gin.Context) {
	userID, exists := c.Get(middleware.ContextUserIDKey)
	if !exists {
		response.Error(c, http.StatusUnauthorized, "User ID not found in context")
		return
	}

	memberID, ok := userID.(string)
	if !ok {
		response.Error(c, http.StatusInternalServerError, "Invalid user ID type")
		return
	}

	ctx := c.Request.Context()
	rooms, err := h.RoomUsecase.GetUserRooms(ctx, memberID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}

	response.Success(c, rooms)
}

func (h *RoomHandler) GetRoomMembers(c *gin.Context) {
	roomID := c.Param("id")
	if roomID == "" {
		response.Error(c, http.StatusBadRequest, "Room ID is required")
		return
	}

	ctx := c.Request.Context()
	members, err := h.RoomUsecase.GetRoomMembers(ctx, roomID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}

	response.Success(c, members)
}
