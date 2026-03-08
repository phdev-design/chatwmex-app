package http

import (
	"net/http"
	"time"

	"chatwmex_backend/internal/delivery/http/middleware"
	"chatwmex_backend/internal/delivery/websocket"
	"chatwmex_backend/internal/domain"
	"chatwmex_backend/pkg/response"
	"chatwmex_backend/pkg/token"

	"github.com/gin-gonic/gin"
)

type AuthHandler struct {
	AuthUsecase domain.AuthUsecase
	JWTSecret   string
	Hub         *websocket.Hub
}

func NewAuthHandler(r *gin.Engine, au domain.AuthUsecase, jwtSecret string, hub *websocket.Hub) {
	handler := &AuthHandler{
		AuthUsecase: au,
		JWTSecret:   jwtSecret,
		Hub:         hub,
	}

	api := r.Group("/api/v1/auth")
	{
		api.GET("/qr/generate", handler.GenerateQRToken)
	}

	protected := r.Group("/api/v1/auth")
	protected.Use(middleware.AuthMiddleware(jwtSecret))
	{
		protected.POST("/qr/confirm", handler.ConfirmQRToken)
	}
}

func (h *AuthHandler) GenerateQRToken(c *gin.Context) {
	ctx := c.Request.Context()
	qrToken, err := h.AuthUsecase.GenerateQRToken(ctx)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "Failed to generate QR token")
		return
	}

	response.Success(c, gin.H{
		"qr_token": qrToken,
	})
}

type ConfirmQRRequest struct {
	QRToken string `json:"qr_token" binding:"required"`
}

func (h *AuthHandler) ConfirmQRToken(c *gin.Context) {
	var req ConfirmQRRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	userID := c.GetString(middleware.ContextUserIDKey)
	if userID == "" {
		response.Error(c, http.StatusUnauthorized, "Unauthorized")
		return
	}

	ctx := c.Request.Context()
	err := h.AuthUsecase.ConfirmQRToken(ctx, req.QRToken, userID)
	if err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	// Generate Web JWT Token for the logged in user
	tokenString, err := token.GenerateToken(userID, h.JWTSecret, 7*24*time.Hour)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "Failed to generate token")
		return
	}

	// Broadcast success event to the QR token "user" socket
	responseMap := map[string]interface{}{
		"token": tokenString,
		"user": map[string]interface{}{
			"id": userID,
		},
	}

	// Note: The Hub.SendNotification sends `{ "event": ..., "data": ... }`.
	// We use req.QRToken as the Target User ID since the web client connects using it.
	h.Hub.SendNotification(req.QRToken, "qr_login_success", responseMap)

	response.Success(c, "QR Login Confirmed")
}
