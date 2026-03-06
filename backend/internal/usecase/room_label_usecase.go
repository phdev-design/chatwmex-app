package usecase

import (
	"context"
	"errors"
	"time"

	"chatwmex_backend/internal/domain"
)

type roomLabelUsecase struct {
	repo    domain.RoomLabelRepository
	timeout time.Duration
}

func NewRoomLabelUsecase(repo domain.RoomLabelRepository, timeout time.Duration) domain.RoomLabelUsecase {
	return &roomLabelUsecase{
		repo:    repo,
		timeout: timeout,
	}
}

func (u *roomLabelUsecase) CreateLabel(c context.Context, userID, name string) (*domain.RoomLabel, error) {
	ctx, cancel := context.WithTimeout(c, u.timeout)
	defer cancel()

	// Find the current max sort order for the user to append to the end
	existingLabels, err := u.repo.GetByUserID(ctx, userID)
	if err != nil {
		return nil, err
	}

	sortOrder := len(existingLabels)

	label := &domain.RoomLabel{
		UserID:    userID,
		Name:      name,
		SortOrder: sortOrder,
		RoomIDs:   []string{},
		IsEnabled: true,
	}

	err = u.repo.Create(ctx, label)
	if err != nil {
		return nil, err
	}
	return label, nil
}

func (u *roomLabelUsecase) GetUserLabels(c context.Context, userID string) ([]*domain.RoomLabel, error) {
	ctx, cancel := context.WithTimeout(c, u.timeout)
	defer cancel()

	return u.repo.GetByUserID(ctx, userID)
}

func (u *roomLabelUsecase) UpdateLabel(c context.Context, userID, labelID, name string, isEnabled bool) (*domain.RoomLabel, error) {
	ctx, cancel := context.WithTimeout(c, u.timeout)
	defer cancel()

	label, err := u.repo.GetByID(ctx, labelID)
	if err != nil {
		return nil, err
	}
	if label.UserID != userID {
		return nil, errors.New("unauthorized")
	}

	label.Name = name
	label.IsEnabled = isEnabled

	err = u.repo.Update(ctx, label)
	if err != nil {
		return nil, err
	}

	return label, nil
}

func (u *roomLabelUsecase) DeleteLabel(c context.Context, userID, labelID string) error {
	ctx, cancel := context.WithTimeout(c, u.timeout)
	defer cancel()

	// The repository method itself checks for UserID
	return u.repo.Delete(ctx, labelID, userID)
}

func (u *roomLabelUsecase) ReorderLabels(c context.Context, userID string, orderedIDs []string) error {
	ctx, cancel := context.WithTimeout(c, u.timeout)
	defer cancel()

	return u.repo.ReorderLabels(ctx, userID, orderedIDs)
}

func (u *roomLabelUsecase) AddRoomToLabel(c context.Context, userID, labelID, roomID string) error {
	ctx, cancel := context.WithTimeout(c, u.timeout)
	defer cancel()

	label, err := u.repo.GetByID(ctx, labelID)
	if err != nil {
		return err
	}
	if label.UserID != userID {
		return errors.New("unauthorized")
	}

	// Check if already in label
	for _, id := range label.RoomIDs {
		if id == roomID {
			return nil // Nothing to do
		}
	}

	label.RoomIDs = append(label.RoomIDs, roomID)
	return u.repo.Update(ctx, label)
}

func (u *roomLabelUsecase) RemoveRoomFromLabel(c context.Context, userID, labelID, roomID string) error {
	ctx, cancel := context.WithTimeout(c, u.timeout)
	defer cancel()

	label, err := u.repo.GetByID(ctx, labelID)
	if err != nil {
		return err
	}
	if label.UserID != userID {
		return errors.New("unauthorized")
	}

	filtered := []string{}
	for _, id := range label.RoomIDs {
		if id != roomID {
			filtered = append(filtered, id)
		}
	}

	label.RoomIDs = filtered
	return u.repo.Update(ctx, label)
}
