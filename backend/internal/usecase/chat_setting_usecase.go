package usecase

import (
	"context"
	"time"

	"chatwmex_backend/internal/domain"
)

type chatSettingUsecase struct {
	repo domain.ChatSettingRepository
}

// NewChatSettingUsecase will create new an chatSettingUsecase object representation of domain.ChatSettingUsecase interface
func NewChatSettingUsecase(repo domain.ChatSettingRepository) domain.ChatSettingUsecase {
	return &chatSettingUsecase{
		repo: repo,
	}
}

func (u *chatSettingUsecase) GetChatSetting(ctx context.Context, chatID string) (*domain.ChatSetting, error) {
	return u.repo.GetSetting(ctx, chatID)
}

func (u *chatSettingUsecase) UpdateDisappearingTimer(ctx context.Context, chatID string, timerSeconds int) (*domain.ChatSetting, error) {
	setting := &domain.ChatSetting{
		ChatID:            chatID,
		DisappearingTimer: timerSeconds,
	}
	err := u.repo.UpsertSetting(ctx, setting)
	if err != nil {
		return nil, err
	}
	return u.repo.GetSetting(ctx, chatID)
}

func (u *chatSettingUsecase) UpdateMuteUntil(ctx context.Context, chatID string, muteUntil *int64) (*domain.ChatSetting, error) {
	setting, err := u.repo.GetSetting(ctx, chatID)
	if err != nil || setting == nil {
		setting = &domain.ChatSetting{ChatID: chatID}
	}
	setting.MuteUntil = muteUntil
	setting.UpdatedAt = time.Now()
	if err := u.repo.UpsertSetting(ctx, setting); err != nil {
		return nil, err
	}
	return u.repo.GetSetting(ctx, chatID)
}

func (u *chatSettingUsecase) UpdateMediaSettings(ctx context.Context, chatID string, saveToCameraRoll, autoDownload, mediaQuality *int) (*domain.ChatSetting, error) {
	setting, err := u.repo.GetSetting(ctx, chatID)
	if err != nil || setting == nil {
		setting = &domain.ChatSetting{ChatID: chatID}
	}
	setting.SaveToCameraRoll = saveToCameraRoll
	setting.AutoDownload = autoDownload
	setting.MediaQuality = mediaQuality
	setting.UpdatedAt = time.Now()
	if err := u.repo.UpsertSetting(ctx, setting); err != nil {
		return nil, err
	}
	return u.repo.GetSetting(ctx, chatID)
}
