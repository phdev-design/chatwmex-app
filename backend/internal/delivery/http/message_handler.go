package http

import (
	"net/http"
	"strconv"
	"time"

	"chatwmex_backend/internal/delivery/http/middleware"
	ws "chatwmex_backend/internal/delivery/websocket"
	"chatwmex_backend/internal/domain"
	"chatwmex_backend/pkg/response"

	"github.com/gin-gonic/gin"
)

type MessageHandler struct {
	MessageUsecase domain.MessageUsecase
	Hub            *ws.Hub
}

// NewMessageHandler initializes the message handler and registers routes.
func NewMessageHandler(r *gin.Engine, mu domain.MessageUsecase, hub *ws.Hub, authMiddleware gin.HandlerFunc) {
	handler := &MessageHandler{
		MessageUsecase: mu,
		Hub:            hub,
	}

	api := r.Group("/api/v1/messages")
	api.Use(authMiddleware)
	{
		api.POST("/send", handler.SendMessage)
		api.GET("/history", handler.GetHistory)
		api.POST("/read/batch", handler.MarkMessagesRead)
		api.POST("/read", handler.MarkAsRead)
		api.POST("/:id/reactions", handler.ToggleReaction)
		api.PATCH("/:id/unsend", handler.UnsendMessage)
		api.DELETE("/:id", handler.DeleteMessage)
	}
}

// SendMessageRequest defines the request body for sending a message.
type SendMessageRequest struct {
	ReceiverID string `json:"receiver_id"`
	RoomID     string `json:"room_id"`
	Content    string `json:"content" binding:"required"`
	Type       string `json:"type"` // Optional, default "text"
}

// SendMessage handles sending a message via HTTP.
func (h *MessageHandler) SendMessage(c *gin.Context) {
	userID, exists := c.Get(middleware.ContextUserIDKey)
	if !exists {
		response.Error(c, http.StatusUnauthorized, "User ID not found in context")
		return
	}

	var req SendMessageRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	senderID, ok := userID.(string)
	if !ok {
		response.Error(c, http.StatusInternalServerError, "Invalid user ID type")
		return
	}

	// Ensure Type is set
	if req.Type == "" {
		req.Type = "text"
	}

	msg := &domain.Message{
		SenderID:   senderID,
		ReceiverID: req.ReceiverID,
		RoomID:     req.RoomID,
		Content:    req.Content,
		Type:       req.Type,
		CreatedAt:  time.Now(),
	}

	ctx := c.Request.Context()
	err := h.MessageUsecase.SendMessage(ctx, msg)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}

	response.Success(c, msg)
}

// GetHistory handles retrieving chat history.
func (h *MessageHandler) GetHistory(c *gin.Context) {
	userID, exists := c.Get(middleware.ContextUserIDKey)
	if !exists {
		response.Error(c, http.StatusUnauthorized, "User ID not found in context")
		return
	}

	contactID := c.Query("contactID")
	if contactID == "" {
		contactID = c.Query("contactId")
	}
	if contactID == "" {
		contactID = c.Query("contact_id")
	}
	if contactID == "" {
		response.Error(c, http.StatusBadRequest, "contactID is required")
		return
	}

	limitStr := c.DefaultQuery("limit", "20")
	limit, err := strconv.Atoi(limitStr)
	if err != nil {
		response.Error(c, http.StatusBadRequest, "Invalid limit parameter")
		return
	}

	offsetStr := c.DefaultQuery("offset", "0")
	offset, err := strconv.Atoi(offsetStr)
	if err != nil {
		response.Error(c, http.StatusBadRequest, "Invalid offset parameter")
		return
	}

	senderID, ok := userID.(string)
	if !ok {
		response.Error(c, http.StatusInternalServerError, "Invalid user ID type")
		return
	}

	ctx := c.Request.Context()
	messages, err := h.MessageUsecase.GetHistory(ctx, senderID, contactID, limit, offset)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}

	response.Success(c, messages)
}

type MarkReadRequest struct {
	ConversationID string `json:"conversation_id" binding:"required"` // UserID (for DM) or RoomID
	IsRoom         bool   `json:"is_room"`
}

type MarkMessagesReadRequest struct {
	MessageIDs []string `json:"message_ids" binding:"required"`
}

func (h *MessageHandler) MarkMessagesRead(c *gin.Context) {
	userID, exists := c.Get(middleware.ContextUserIDKey)
	if !exists {
		response.Error(c, http.StatusUnauthorized, "User ID not found in context")
		return
	}

	var req MarkMessagesReadRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	if len(req.MessageIDs) == 0 {
		response.Error(c, http.StatusBadRequest, "message_ids is required")
		return
	}

	userIDStr, ok := userID.(string)
	if !ok {
		response.Error(c, http.StatusInternalServerError, "Invalid user ID type")
		return
	}

	ctx := c.Request.Context()
	if err := h.MessageUsecase.MarkMessagesAsReadBy(ctx, userIDStr, req.MessageIDs); err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}

	roomMap, err := h.MessageUsecase.GetRoomMessageMap(ctx, req.MessageIDs)
	if err == nil && h.Hub != nil {
		for roomID, messageIDs := range roomMap {
			if roomID == "" || len(messageIDs) == 0 {
				continue
			}
			h.Hub.BroadcastRoomReadReceipt(roomID, messageIDs, userIDStr)
		}
	}

	response.Success(c, "Messages marked as read")
}

func (h *MessageHandler) MarkAsRead(c *gin.Context) {
	userID, exists := c.Get(middleware.ContextUserIDKey)
	if !exists {
		response.Error(c, http.StatusUnauthorized, "User ID not found in context")
		return
	}

	var req MarkReadRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	userIDStr, ok := userID.(string)
	if !ok {
		response.Error(c, http.StatusInternalServerError, "Invalid user ID type")
		return
	}

	ctx := c.Request.Context()
	err := h.MessageUsecase.MarkAsRead(ctx, userIDStr, req.ConversationID, req.IsRoom)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}

	response.Success(c, "Messages marked as read")
}

type ToggleReactionRequest struct {
	Emoji string `json:"emoji" binding:"required"`
}

func (h *MessageHandler) ToggleReaction(c *gin.Context) {
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
	messageID := c.Param("id")
	if messageID == "" {
		response.Error(c, http.StatusBadRequest, "Message ID is required")
		return
	}

	var req ToggleReactionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	if req.Emoji == "" {
		response.Error(c, http.StatusBadRequest, "emoji is required")
		return
	}

	ctx := c.Request.Context()
	updated, err := h.MessageUsecase.ToggleReaction(ctx, messageID, userIDStr, req.Emoji)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}

	if h.Hub != nil {
		h.Hub.BroadcastMessageReaction(updated)
	}
	response.Success(c, updated)
}

func (h *MessageHandler) UnsendMessage(c *gin.Context) {
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
	messageID := c.Param("id")
	if messageID == "" {
		response.Error(c, http.StatusBadRequest, "Message ID is required")
		return
	}

	ctx := c.Request.Context()
	updated, err := h.MessageUsecase.UnsendMessage(ctx, messageID, userIDStr)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	if h.Hub != nil {
		h.Hub.BroadcastMessageUnsent(updated)
	}
	response.Success(c, updated)
}

func (h *MessageHandler) DeleteMessage(c *gin.Context) {
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
	messageID := c.Param("id")
	if messageID == "" {
		response.Error(c, http.StatusBadRequest, "Message ID is required")
		return
	}
	ctx := c.Request.Context()
	if err := h.MessageUsecase.DeleteMessage(ctx, messageID, userIDStr); err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, "Message deleted successfully")
}
