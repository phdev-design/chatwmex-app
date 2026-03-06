package http

import (
	"net/http"

	"chatwmex_backend/internal/domain"

	"github.com/gin-gonic/gin"
)

type ChatSettingHandler struct {
	usecase domain.ChatSettingUsecase
}

func NewChatSettingHandler(r *gin.Engine, usecase domain.ChatSettingUsecase, authMiddleware gin.HandlerFunc) {
	handler := &ChatSettingHandler{
		usecase: usecase,
	}

	// `/api/v1/chats/:id/settings`
	group := r.Group("/api/v1/chats")
	group.Use(authMiddleware)
	{
		group.GET("/:id/settings", handler.GetSettings)
		group.PUT("/:id/settings", handler.UpdateSettings)
	}
}

func (h *ChatSettingHandler) GetSettings(c *gin.Context) {
	chatID := c.Param("id")
	if chatID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "chat ID is required"})
		return
	}

	// In a real app we'd verify if the user has access to this chat.
	// For DMs, the ID could be user_id. We might need logic in usecase to sort and format the "chatID".
	// Let's assume the frontend passes the exact room_id, or the contact's user_id.

	// If it's a DM, frontend might just pass the friend's userID. We need to normalize it to the A_B format.
	userID := c.GetString("user_id")
	if chatID != "" && len(chatID) == 24 {
		// It's likely an ObjectID (Room ID). Do nothing.
	} else {
		// It might be a user ID. Normalize the DM chat ID here for simplicity.
		// (A more strict approach would check the database).
		if userID < chatID {
			chatID = userID + "_" + chatID
		} else {
			chatID = chatID + "_" + userID
		}
	}

	setting, err := h.usecase.GetChatSetting(c.Request.Context(), chatID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": setting})
}

func (h *ChatSettingHandler) UpdateSettings(c *gin.Context) {
	chatID := c.Param("id")
	if chatID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "chat ID is required"})
		return
	}

	userID := c.GetString("user_id")
	if chatID != "" && len(chatID) == 24 {
		// It's likely an ObjectID (Room ID). Do nothing.
	} else {
		if userID < chatID {
			chatID = userID + "_" + chatID
		} else {
			chatID = chatID + "_" + userID
		}
	}

	var req struct {
		DisappearingTimer *int   `json:"disappearing_timer"`
		MuteUntil         *int64 `json:"mute_until"`
		SaveToCameraRoll  *int   `json:"save_to_camera_roll"`
		AutoDownload      *int   `json:"auto_download"`
		MediaQuality      *int   `json:"media_quality"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var setting *domain.ChatSetting
	var err error

	if req.SaveToCameraRoll != nil || req.AutoDownload != nil || req.MediaQuality != nil {
		setting, err = h.usecase.UpdateMediaSettings(c.Request.Context(), chatID, req.SaveToCameraRoll, req.AutoDownload, req.MediaQuality)
	} else if req.MuteUntil != nil {
		setting, err = h.usecase.UpdateMuteUntil(c.Request.Context(), chatID, req.MuteUntil)
	} else if req.DisappearingTimer != nil {
		setting, err = h.usecase.UpdateDisappearingTimer(c.Request.Context(), chatID, *req.DisappearingTimer)
	} else {
		c.JSON(http.StatusBadRequest, gin.H{"error": "no valid field to update"})
		return
	}

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": setting})
}
