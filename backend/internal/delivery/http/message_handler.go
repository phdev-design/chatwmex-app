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

type MessageHandler struct {
	MessageUsecase domain.MessageUsecase
}

// NewMessageHandler initializes the message handler and registers routes.
func NewMessageHandler(r *gin.Engine, mu domain.MessageUsecase, authMiddleware gin.HandlerFunc) {
	handler := &MessageHandler{
		MessageUsecase: mu,
	}

	api := r.Group("/api/v1/messages")
	api.Use(authMiddleware)
	{
		api.POST("/send", handler.SendMessage)
		api.GET("/history", handler.GetHistory)
		api.POST("/read", handler.MarkAsRead)
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
