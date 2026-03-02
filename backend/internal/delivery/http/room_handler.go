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
		api.DELETE("/:id/members/:memberId", handler.KickMember)
		api.DELETE("/:id", handler.DeleteRoom)
		api.GET("/my", handler.GetUserRooms)
		api.GET("/:id/members", handler.GetRoomMembers)
	}
}

type CreateRoomRequest struct {
	Name      string   `json:"name" binding:"required"`
	MemberIDs []string `json:"member_ids"`
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
	room, err := h.RoomUsecase.CreateRoom(ctx, req.Name, ownerID, req.MemberIDs)
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

func (h *RoomHandler) KickMember(c *gin.Context) {
	userID, exists := c.Get(middleware.ContextUserIDKey)
	if !exists {
		response.Error(c, http.StatusUnauthorized, "User ID not found in context")
		return
	}

	roomID := c.Param("id")
	memberID := c.Param("memberId")
	if roomID == "" || memberID == "" {
		response.Error(c, http.StatusBadRequest, "Room ID and member ID are required")
		return
	}

	ownerID, ok := userID.(string)
	if !ok {
		response.Error(c, http.StatusInternalServerError, "Invalid user ID type")
		return
	}

	ctx := c.Request.Context()
	err := h.RoomUsecase.KickMember(ctx, roomID, ownerID, memberID)
	if err != nil {
		if err.Error() == "forbidden" {
			response.Error(c, http.StatusForbidden, "Only owner can remove members")
			return
		}
		if err.Error() == "cannot_remove_owner" {
			response.Error(c, http.StatusBadRequest, "Owner cannot be removed")
			return
		}
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}

	response.Success(c, "Member removed")
}

func (h *RoomHandler) DeleteRoom(c *gin.Context) {
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

	ownerID, ok := userID.(string)
	if !ok {
		response.Error(c, http.StatusInternalServerError, "Invalid user ID type")
		return
	}

	ctx := c.Request.Context()
	err := h.RoomUsecase.DeleteRoom(ctx, roomID, ownerID)
	if err != nil {
		if err.Error() == "forbidden" {
			response.Error(c, http.StatusForbidden, "Only owner can delete room")
			return
		}
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}

	response.Success(c, "Room deleted")
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
