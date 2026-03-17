package http

import (
	"net/http"
	"strings"

	"chatwmex_backend/internal/delivery/http/middleware"
	"chatwmex_backend/internal/domain"
	"chatwmex_backend/pkg/response"

	"github.com/gin-gonic/gin"
)

// PrivacySettingHandler handles GET/PUT /api/v1/privacy-settings.
type PrivacySettingHandler struct {
	usecase domain.PrivacySettingUsecase
}

// NewPrivacySettingHandler registers the privacy settings routes on the router.
func NewPrivacySettingHandler(r *gin.Engine, usecase domain.PrivacySettingUsecase, authMiddleware gin.HandlerFunc) {
	handler := &PrivacySettingHandler{usecase: usecase}

	group := r.Group("/api/v1/privacy-settings")
	group.Use(authMiddleware)
	{
		group.GET("", handler.GetPrivacySetting)
		group.PUT("", handler.UpdatePrivacySetting)
	}
}

// GetPrivacySetting handles GET /api/v1/privacy-settings.
// Returns the authenticated user's privacy setting (defaults if none stored).
func (h *PrivacySettingHandler) GetPrivacySetting(c *gin.Context) {
	userID, exists := c.Get(middleware.ContextUserIDKey)
	if !exists {
		response.Error(c, http.StatusUnauthorized, "User ID not found in context")
		return
	}

	setting, err := h.usecase.GetPrivacySetting(c.Request.Context(), userID.(string))
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}

	response.Success(c, setting)
}

// UpdatePrivacySetting handles PUT /api/v1/privacy-settings.
// Decodes a partial UpdatePrivacySettingRequest and applies the update.
// Returns 400 on validation errors, 500 on other errors.
func (h *PrivacySettingHandler) UpdatePrivacySetting(c *gin.Context) {
	userID, exists := c.Get(middleware.ContextUserIDKey)
	if !exists {
		response.Error(c, http.StatusUnauthorized, "User ID not found in context")
		return
	}

	var req domain.UpdatePrivacySettingRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	updated, err := h.usecase.UpdatePrivacySetting(c.Request.Context(), userID.(string), req)
	if err != nil {
		if strings.Contains(err.Error(), "invalid privacy level") {
			response.Error(c, http.StatusBadRequest, err.Error())
			return
		}
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}

	response.Success(c, updated)
}
