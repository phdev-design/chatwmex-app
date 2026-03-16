package http

import (
	"net/http"

	"chatwmex_backend/internal/delivery/http/middleware"
	"chatwmex_backend/internal/domain"
	"chatwmex_backend/pkg/response"

	"github.com/gin-gonic/gin"
)

// LinkedDeviceHandler handles HTTP requests for linked device management.
type LinkedDeviceHandler struct {
	LinkedDeviceUsecase domain.LinkedDeviceUsecase
}

// NewLinkedDeviceHandler registers linked device routes and returns the handler.
func NewLinkedDeviceHandler(r *gin.Engine, ldu domain.LinkedDeviceUsecase, authMiddleware gin.HandlerFunc) {
	handler := &LinkedDeviceHandler{
		LinkedDeviceUsecase: ldu,
	}

	api := r.Group("/api/v1/devices")
	api.Use(authMiddleware)
	{
		api.GET("/linked", handler.GetLinkedDevices)
		api.DELETE("/linked/:id", handler.UnlinkDevice)
		api.POST("/session-key", handler.DeliverSessionKey)
	}
}

// GetLinkedDevices returns all linked devices for the authenticated user.
func (h *LinkedDeviceHandler) GetLinkedDevices(c *gin.Context) {
	userID := c.GetString(middleware.ContextUserIDKey)
	if userID == "" {
		response.Error(c, http.StatusUnauthorized, "unauthorized")
		return
	}

	devices, err := h.LinkedDeviceUsecase.GetLinkedDevices(c.Request.Context(), userID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}

	response.Success(c, devices)
}

// UnlinkDevice removes a linked device for the authenticated user.
func (h *LinkedDeviceHandler) UnlinkDevice(c *gin.Context) {
	userID := c.GetString(middleware.ContextUserIDKey)
	if userID == "" {
		response.Error(c, http.StatusUnauthorized, "unauthorized")
		return
	}

	deviceID := c.Param("id")
	if deviceID == "" {
		response.Error(c, http.StatusBadRequest, "device ID is required")
		return
	}

	err := h.LinkedDeviceUsecase.UnlinkDevice(c.Request.Context(), userID, deviceID)
	if err != nil {
		switch err.Error() {
		case "device_not_found":
			response.Error(c, http.StatusNotFound, "device_not_found")
		case "unauthorized":
			response.Error(c, http.StatusForbidden, "unauthorized")
		default:
			response.Error(c, http.StatusInternalServerError, err.Error())
		}
		return
	}

	response.Success(c, gin.H{"message": "device unlinked successfully"})
}

// DeliverSessionKeyRequest represents the request body for session key delivery.
type DeliverSessionKeyRequest struct {
	DeviceID        string `json:"device_id" binding:"required"`
	EncryptedKey    string `json:"encrypted_key" binding:"required"`
	SenderPublicKey string `json:"sender_public_key"`
}

// DeliverSessionKey sends an encrypted session key to a linked device via WebSocket.
func (h *LinkedDeviceHandler) DeliverSessionKey(c *gin.Context) {
	userID := c.GetString(middleware.ContextUserIDKey)
	if userID == "" {
		response.Error(c, http.StatusUnauthorized, "unauthorized")
		return
	}

	var req DeliverSessionKeyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	err := h.LinkedDeviceUsecase.DeliverSessionKey(c.Request.Context(), userID, req.DeviceID, req.EncryptedKey, req.SenderPublicKey)
	if err != nil {
		switch err.Error() {
		case "device_not_found":
			response.Error(c, http.StatusNotFound, "device_not_found")
		case "unauthorized":
			response.Error(c, http.StatusForbidden, "unauthorized")
		case "session_key_delivery_failed":
			response.Error(c, http.StatusInternalServerError, "session_key_delivery_failed")
		default:
			response.Error(c, http.StatusInternalServerError, err.Error())
		}
		return
	}

	response.Success(c, gin.H{"message": "session key delivered successfully"})
}
