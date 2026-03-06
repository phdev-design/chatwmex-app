package http

import (
	"net/http"

	"chatwmex_backend/internal/domain"
	"chatwmex_backend/pkg/response"

	"github.com/gin-gonic/gin"
)

type RoomLabelHandler struct {
	labelUsecase domain.RoomLabelUsecase
}

func NewRoomLabelHandler(r *gin.Engine, labelUsecase domain.RoomLabelUsecase, authMiddleware gin.HandlerFunc) {
	handler := &RoomLabelHandler{
		labelUsecase: labelUsecase,
	}

	labelsGroup := r.Group("/api/v1/labels")
	labelsGroup.Use(authMiddleware)
	{
		labelsGroup.GET("", handler.GetUserLabels)
		labelsGroup.POST("", handler.CreateLabel)
		// reorder must be before :id to prevent gin from matching :id = reorder
		labelsGroup.PUT("/reorder", handler.ReorderLabels)
		labelsGroup.PUT("/:id", handler.UpdateLabel)
		labelsGroup.DELETE("/:id", handler.DeleteLabel)
		labelsGroup.POST("/:id/rooms", handler.AddRoomToLabel)
		labelsGroup.DELETE("/:id/rooms/:room_id", handler.RemoveRoomFromLabel)
	}
}

func (h *RoomLabelHandler) GetUserLabels(c *gin.Context) {
	userID := c.GetString("user_id")

	labels, err := h.labelUsecase.GetUserLabels(c.Request.Context(), userID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}

	response.Success(c, labels)
}

func (h *RoomLabelHandler) CreateLabel(c *gin.Context) {
	userID := c.GetString("user_id")

	var req struct {
		Name string `json:"name" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	label, err := h.labelUsecase.CreateLabel(c.Request.Context(), userID, req.Name)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}

	response.Success(c, label)
}

func (h *RoomLabelHandler) UpdateLabel(c *gin.Context) {
	userID := c.GetString("user_id")
	labelID := c.Param("id")

	var req struct {
		Name      string `json:"name" binding:"required"`
		IsEnabled bool   `json:"is_enabled"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	label, err := h.labelUsecase.UpdateLabel(c.Request.Context(), userID, labelID, req.Name, req.IsEnabled)
	if err != nil {
		if err.Error() == "unauthorized" {
			response.Error(c, http.StatusForbidden, "not authorized to update this label")
			return
		}
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}

	response.Success(c, label)
}

func (h *RoomLabelHandler) DeleteLabel(c *gin.Context) {
	userID := c.GetString("user_id")
	labelID := c.Param("id")

	err := h.labelUsecase.DeleteLabel(c.Request.Context(), userID, labelID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}

	response.Success(c, gin.H{"message": "label deleted successfully"})
}

func (h *RoomLabelHandler) ReorderLabels(c *gin.Context) {
	userID := c.GetString("user_id")

	var req struct {
		OrderedIDs []string `json:"ordered_ids" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	err := h.labelUsecase.ReorderLabels(c.Request.Context(), userID, req.OrderedIDs)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}

	response.Success(c, gin.H{"message": "labels reordered successfully"})
}

func (h *RoomLabelHandler) AddRoomToLabel(c *gin.Context) {
	userID := c.GetString("user_id")
	labelID := c.Param("id")

	var req struct {
		RoomID string `json:"room_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	err := h.labelUsecase.AddRoomToLabel(c.Request.Context(), userID, labelID, req.RoomID)
	if err != nil {
		if err.Error() == "unauthorized" {
			response.Error(c, http.StatusForbidden, "not authorized to update this label")
			return
		}
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}

	response.Success(c, gin.H{"message": "room added to label successfully"})
}

func (h *RoomLabelHandler) RemoveRoomFromLabel(c *gin.Context) {
	userID := c.GetString("user_id")
	labelID := c.Param("id")
	roomID := c.Param("room_id")

	err := h.labelUsecase.RemoveRoomFromLabel(c.Request.Context(), userID, labelID, roomID)
	if err != nil {
		if err.Error() == "unauthorized" {
			response.Error(c, http.StatusForbidden, "not authorized to update this label")
			return
		}
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}

	response.Success(c, gin.H{"message": "room removed from label successfully"})
}
