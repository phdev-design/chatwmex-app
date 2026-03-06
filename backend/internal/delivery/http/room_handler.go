package http

import (
	"net/http"
	"strconv"
	"time"

	"chatwmex_backend/internal/delivery/http/middleware"
	"chatwmex_backend/internal/domain"
	"chatwmex_backend/pkg/response"

	"github.com/gin-gonic/gin"
)

type RoomHandler struct {
	RoomUsecase domain.RoomUsecase
	UserUsecase domain.UserUsecase
}

func NewRoomHandler(r *gin.Engine, ru domain.RoomUsecase, uu domain.UserUsecase, authMiddleware gin.HandlerFunc) {
	handler := &RoomHandler{
		RoomUsecase: ru,
		UserUsecase: uu,
	}

	api := r.Group("/api/v1/rooms")
	api.Use(authMiddleware)
	{
		api.POST("", handler.CreateRoom)
		api.POST("/:id/join", handler.JoinRoom)
		api.POST("/:id/leave", handler.LeaveRoom)
		api.PATCH("/:id", handler.UpdateRoom)
		api.DELETE("/:id/members/:memberId", handler.KickMember)
		api.DELETE("/:id", handler.DeleteRoom)
		api.GET("/my", handler.GetUserRooms)
		api.GET("/:id/media", handler.GetRoomMedia)
		api.GET("/:id/members", handler.GetRoomMembers)
		api.GET("/:id/member-profiles", handler.GetRoomMemberProfiles)
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
	keyword := c.Query("q")

	ctx := c.Request.Context()
	rooms, err := h.RoomUsecase.GetUserRooms(ctx, memberID, keyword)
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

func (h *RoomHandler) GetRoomMedia(c *gin.Context) {
	userID, exists := c.Get(middleware.ContextUserIDKey)
	if !exists {
		response.Error(c, http.StatusUnauthorized, "User ID not found in context")
		return
	}

	userIDStr, ok := userID.(string)
	if !ok {
		response.Error(c, http.StatusInternalServerError, "Invalid user ID type")
		return
	}

	roomID := c.Param("id")
	if roomID == "" {
		response.Error(c, http.StatusBadRequest, "Room ID is required")
		return
	}

	reqType := c.DefaultQuery("type", "media")
	cursor := c.DefaultQuery("cursor", "")
	limitStr := c.DefaultQuery("limit", "20")
	limit, err := strconv.Atoi(limitStr)
	if err != nil {
		response.Error(c, http.StatusBadRequest, "Invalid limit parameter")
		return
	}

	ctx := c.Request.Context()
	media, hasMore, err := h.RoomUsecase.GetRoomMedia(ctx, userIDStr, roomID, reqType, cursor, limit)
	if err != nil {
		switch err.Error() {
		case "invalid_room_id":
			response.Error(c, http.StatusBadRequest, "Invalid room ID")
		case "room_not_found":
			response.Error(c, http.StatusNotFound, "Room not found")
		case "forbidden":
			response.Error(c, http.StatusForbidden, "Only room members can access media")
		case "invalid_type":
			response.Error(c, http.StatusBadRequest, "Invalid type parameter")
		default:
			response.Error(c, http.StatusInternalServerError, err.Error())
		}
		return
	}

	nextCursor := ""
	if len(media) > 0 && hasMore {
		nextCursor = media[len(media)-1].CreatedAt.UTC().Format(time.RFC3339Nano)
	}

	response.Success(c, gin.H{
		"data":        media,
		"next_cursor": nextCursor,
		"has_more":    hasMore,
	})
}

func (h *RoomHandler) GetRoomMemberProfiles(c *gin.Context) {
	roomID := c.Param("id")
	if roomID == "" {
		response.Error(c, http.StatusBadRequest, "Room ID is required")
		return
	}

	ctx := c.Request.Context()
	memberIDs, err := h.RoomUsecase.GetRoomMembers(ctx, roomID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}

	profiles := make([]map[string]interface{}, 0, len(memberIDs))
	for _, memberID := range memberIDs {
		user, userErr := h.UserUsecase.GetUserProfile(ctx, memberID)
		if userErr != nil || user == nil {
			continue
		}
		profiles = append(profiles, map[string]interface{}{
			"id":         user.ID,
			"username":   user.Username,
			"avatar_url": user.AvatarURL,
		})
	}

	response.Success(c, profiles)
}

type UpdateRoomRequest struct {
	Name      *string `json:"name"`
	AvatarURL *string `json:"avatar_url"`
}

func (h *RoomHandler) UpdateRoom(c *gin.Context) {
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

	var req UpdateRoomRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	ctx := c.Request.Context()
	err := h.RoomUsecase.UpdateRoom(ctx, roomID, ownerID, req.Name, req.AvatarURL)
	if err != nil {
		if err.Error() == "forbidden" {
			response.Error(c, http.StatusForbidden, "Only owner can update room")
			return
		}
		if err.Error() == "room not found" {
			response.Error(c, http.StatusNotFound, "Room not found")
			return
		}
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}

	// 成功後取得最新資訊，為了發送 WebSocket Event
	updatedRoom, err := h.RoomUsecase.GetUserRooms(ctx, ownerID, "") // Workaround to get Room Info since we updated it. A better way is pulling GetByID, but the usecase does not export GetByID.
	var targetRoom *domain.Room
	// Simple traversal to locate it amongst user rooms.
	if err == nil {
		for _, r := range updatedRoom {
			if r.ID == roomID {
				targetRoom = r
				break
			}
		}
	}

	if targetRoom != nil {
		hubValues, exists := c.Get("hub")
		if exists {
			if hub, ok := hubValues.(interface {
				BroadcastRoomEvent(roomID string, eventType string, data interface{})
			}); ok {
				hub.BroadcastRoomEvent(roomID, "room_updated", gin.H{
					"room_id":    roomID,
					"name":       targetRoom.Name,
					"avatar_url": targetRoom.AvatarURL,
				})
			}
		}
	}

	response.Success(c, "Room updated successfully")
}
