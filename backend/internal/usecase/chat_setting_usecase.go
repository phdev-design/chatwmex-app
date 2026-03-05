package usecase

import (
	"context"

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
