package usecase

import (
	"context"
	"fmt"

	"chatwmex_backend/internal/domain"
)

type privacySettingUsecase struct {
	privacyRepo domain.UserPrivacyRepository
	friendRepo  domain.FriendRepository
}

// NewPrivacySettingUsecase creates a new PrivacySettingUsecase.
func NewPrivacySettingUsecase(privacyRepo domain.UserPrivacyRepository, friendRepo domain.FriendRepository) domain.PrivacySettingUsecase {
	return &privacySettingUsecase{
		privacyRepo: privacyRepo,
		friendRepo:  friendRepo,
	}
}

// defaultPrivacySetting returns the default privacy setting for a user (lazy default, not persisted).
func defaultPrivacySetting(userID string) *domain.PrivacySetting {
	return &domain.PrivacySetting{
		UserID:              userID,
		LastSeenPrivacy:     domain.PrivacyLevelEveryone,
		OnlineStatusPrivacy: domain.PrivacyLevelEveryone,
		ProfilePhotoPrivacy: domain.PrivacyLevelEveryone,
		ReadReceiptsEnabled: true,
	}
}

// strictestPrivacySetting returns the strictest possible defaults (used on error).
func strictestPrivacySetting(userID string) *domain.PrivacySetting {
	return &domain.PrivacySetting{
		UserID:              userID,
		LastSeenPrivacy:     domain.PrivacyLevelNobody,
		OnlineStatusPrivacy: domain.PrivacyLevelNobody,
		ProfilePhotoPrivacy: domain.PrivacyLevelNobody,
		ReadReceiptsEnabled: false,
	}
}

// GetPrivacySetting returns the user's privacy setting, or defaults if no record exists.
func (u *privacySettingUsecase) GetPrivacySetting(ctx context.Context, userID string) (*domain.PrivacySetting, error) {
	setting, err := u.privacyRepo.GetPrivacySetting(ctx, userID)
	if err != nil {
		return nil, err
	}
	if setting == nil {
		return defaultPrivacySetting(userID), nil
	}
	return setting, nil
}

// UpdatePrivacySetting validates and applies a partial update to the user's privacy setting.
func (u *privacySettingUsecase) UpdatePrivacySetting(ctx context.Context, userID string, req domain.UpdatePrivacySettingRequest) (*domain.PrivacySetting, error) {
	// Validate all non-nil PrivacyLevel fields
	if req.LastSeenPrivacy != nil {
		if err := validatePrivacyLevel(*req.LastSeenPrivacy); err != nil {
			return nil, err
		}
	}
	if req.OnlineStatusPrivacy != nil {
		if err := validatePrivacyLevel(*req.OnlineStatusPrivacy); err != nil {
			return nil, err
		}
	}
	if req.ProfilePhotoPrivacy != nil {
		if err := validatePrivacyLevel(*req.ProfilePhotoPrivacy); err != nil {
			return nil, err
		}
	}

	// Get current setting (or defaults)
	current, err := u.GetPrivacySetting(ctx, userID)
	if err != nil {
		return nil, err
	}

	// Apply only non-nil fields (partial update)
	if req.LastSeenPrivacy != nil {
		current.LastSeenPrivacy = *req.LastSeenPrivacy
	}
	if req.OnlineStatusPrivacy != nil {
		current.OnlineStatusPrivacy = *req.OnlineStatusPrivacy
	}
	if req.ProfilePhotoPrivacy != nil {
		current.ProfilePhotoPrivacy = *req.ProfilePhotoPrivacy
	}
	if req.ReadReceiptsEnabled != nil {
		current.ReadReceiptsEnabled = *req.ReadReceiptsEnabled
	}

	// Upsert the merged setting
	if err := u.privacyRepo.UpsertPrivacySetting(ctx, current); err != nil {
		return nil, err
	}

	return current, nil
}

// validatePrivacyLevel returns an error if the level is not in {0, 1, 2}.
func validatePrivacyLevel(level domain.PrivacyLevel) error {
	if level < domain.PrivacyLevelEveryone || level > domain.PrivacyLevelNobody {
		return fmt.Errorf("invalid privacy level %d: must be 0 (Everyone), 1 (Contacts), or 2 (Nobody)", int(level))
	}
	return nil
}

// FilterPresence applies per-subject privacy filtering with reciprocity and linkage rules.
func (u *privacySettingUsecase) FilterPresence(ctx context.Context, viewerID string, subjects map[string]*domain.PresenceInfo) (map[string]*domain.PresenceInfo, error) {
	// Get viewer's own privacy settings
	viewerSetting, err := u.GetPrivacySetting(ctx, viewerID)
	if err != nil {
		// On error, use strictest defaults for viewer (they see nothing)
		viewerSetting = strictestPrivacySetting(viewerID)
	}

	result := make(map[string]*domain.PresenceInfo, len(subjects))

	for subjectID, presence := range subjects {
		filtered := &domain.PresenceInfo{}

		// Get subject's privacy settings; on error apply strictest defaults
		subjectSetting, err := u.GetPrivacySetting(ctx, subjectID)
		if err != nil {
			subjectSetting = strictestPrivacySetting(subjectID)
		}

		// --- Linkage rule ---
		// OnlineStatusPrivacy=Contacts AND LastSeenPrivacy=Nobody → effectiveOnlinePrivacy = Nobody
		effectiveOnlinePrivacy := subjectSetting.OnlineStatusPrivacy
		if effectiveOnlinePrivacy == domain.PrivacyLevelContacts &&
			subjectSetting.LastSeenPrivacy == domain.PrivacyLevelNobody {
			effectiveOnlinePrivacy = domain.PrivacyLevelNobody
		}

		// --- is_online filtering ---
		switch effectiveOnlinePrivacy {
		case domain.PrivacyLevelNobody:
			filtered.IsOnline = false
		case domain.PrivacyLevelContacts:
			isFriend := u.isFriendSafe(ctx, subjectID, viewerID)
			if isFriend && viewerSetting.OnlineStatusPrivacy != domain.PrivacyLevelNobody {
				filtered.IsOnline = presence.IsOnline
			} else {
				filtered.IsOnline = false
			}
		case domain.PrivacyLevelEveryone:
			// Reciprocity: if viewer hides their own online status, they can't see others'
			if viewerSetting.OnlineStatusPrivacy == domain.PrivacyLevelNobody {
				filtered.IsOnline = false
			} else {
				filtered.IsOnline = presence.IsOnline
			}
		}

		// --- last_seen filtering ---
		switch subjectSetting.LastSeenPrivacy {
		case domain.PrivacyLevelNobody:
			filtered.LastSeen = nil
		case domain.PrivacyLevelContacts:
			isFriend := u.isFriendSafe(ctx, subjectID, viewerID)
			if isFriend && viewerSetting.LastSeenPrivacy != domain.PrivacyLevelNobody {
				filtered.LastSeen = presence.LastSeen
			} else {
				filtered.LastSeen = nil
			}
		case domain.PrivacyLevelEveryone:
			// Reciprocity: if viewer hides their own last_seen, they can't see others'
			if viewerSetting.LastSeenPrivacy == domain.PrivacyLevelNobody {
				filtered.LastSeen = nil
			} else {
				filtered.LastSeen = presence.LastSeen
			}
		}

		result[subjectID] = filtered
	}

	return result, nil
}

// isFriendSafe calls IsFriend and treats errors as non-friend (conservative).
func (u *privacySettingUsecase) isFriendSafe(ctx context.Context, userID, friendID string) bool {
	isFriend, err := u.friendRepo.IsFriend(ctx, userID, friendID)
	if err != nil {
		return false
	}
	return isFriend
}

// ShouldShowReadReceipt returns true for group chats always; for DM, both parties must have ReadReceiptsEnabled=true.
// On DB error, fail-open (return true).
func (u *privacySettingUsecase) ShouldShowReadReceipt(ctx context.Context, readerID, senderID string, isGroup bool) (bool, error) {
	if isGroup {
		return true, nil
	}

	// DM: both reader and sender must have ReadReceiptsEnabled=true
	readerSetting, err := u.privacyRepo.GetPrivacySetting(ctx, readerID)
	if err != nil {
		// Fail-open on DB error
		return true, nil
	}
	if readerSetting == nil {
		readerSetting = defaultPrivacySetting(readerID)
	}

	senderSetting, err := u.privacyRepo.GetPrivacySetting(ctx, senderID)
	if err != nil {
		// Fail-open on DB error
		return true, nil
	}
	if senderSetting == nil {
		senderSetting = defaultPrivacySetting(senderID)
	}

	return readerSetting.ReadReceiptsEnabled && senderSetting.ReadReceiptsEnabled, nil
}
