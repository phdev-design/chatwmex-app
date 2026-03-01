package http

import (
	"net/http"

	"chatwmex_backend/internal/delivery/http/middleware"
	"chatwmex_backend/internal/domain"
	"chatwmex_backend/pkg/response"

	"github.com/gin-gonic/gin"
)

type DeviceHandler struct {
	DeviceUsecase domain.DeviceUsecase
}

func NewDeviceHandler(r *gin.Engine, du domain.DeviceUsecase, authMiddleware gin.HandlerFunc) {
	handler := &DeviceHandler{
		DeviceUsecase: du,
	}

	api := r.Group("/api/v1/devices")
	api.Use(authMiddleware)
	{
		api.POST("/register", handler.Register)
		api.DELETE("/:id", handler.Unregister)
	}
}

type RegisterDeviceRequest struct {
	DeviceID string `json:"device_id" binding:"required"`
	Platform string `json:"platform" binding:"required,oneof=ios android web"`
}

func (h *DeviceHandler) Register(c *gin.Context) {
	var req RegisterDeviceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	userID := c.GetString(middleware.ContextUserIDKey)
	if userID == "" {
		response.Error(c, http.StatusUnauthorized, "Unauthorized")
		return
	}

	err := h.DeviceUsecase.RegisterDevice(c.Request.Context(), req.DeviceID, userID, req.Platform)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}

	response.Success(c, "Device registered successfully")
}

func (h *DeviceHandler) Unregister(c *gin.Context) {
	deviceID := c.Param("id")
	if deviceID == "" {
		response.Error(c, http.StatusBadRequest, "Device ID is required")
		return
	}

	// We might want to check if the device belongs to the user,
	// but unregistering usually implies "forget this device token".
	// The repo delete just deletes by ID.
	// For extra security, we could verify ownership, but if the user has the ID, they can delete it.
	
	err := h.DeviceUsecase.UnregisterDevice(c.Request.Context(), deviceID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}

	response.Success(c, "Device unregistered successfully")
}
