package usecase

import (
	"context"
	"sync"
	"testing"
	"time"

	"chatwmex_backend/internal/domain"

	"github.com/stretchr/testify/assert"
	"pgregory.net/rapid"
)

// ---------------------------------------------------------------------------
// In-memory mock: UserPrivacyRepository
// ---------------------------------------------------------------------------

type mockPrivacyRepo struct {
	mu       sync.Mutex
	settings map[string]*domain.PrivacySetting
}

func newMockPrivacyRepo() *mockPrivacyRepo {
	return &mockPrivacyRepo{settings: make(map[string]*domain.PrivacySetting)}
}

func (r *mockPrivacyRepo) GetPrivacySetting(_ context.Context, userID string) (*domain.PrivacySetting, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	s, ok := r.settings[userID]
	if !ok {
		return nil, nil
	}
	cp := *s
	return &cp, nil
}

func (r *mockPrivacyRepo) UpsertPrivacySetting(_ context.Context, setting *domain.PrivacySetting) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	cp := *setting
	r.settings[setting.UserID] = &cp
	return nil
}

// ---------------------------------------------------------------------------
// In-memory mock: FriendRepository
// ---------------------------------------------------------------------------

type mockFriendRepo struct {
	isFriendFn func(userID, friendID string) bool
}

func newMockFriendRepo(isFriend bool) *mockFriendRepo {
	return &mockFriendRepo{isFriendFn: func(_, _ string) bool { return isFriend }}
}

func (r *mockFriendRepo) IsFriend(_ context.Context, userID, friendID string) (bool, error) {
	return r.isFriendFn(userID, friendID), nil
}
func (r *mockFriendRepo) CreateRequest(_ context.Context, _ *domain.FriendRequest) error {
	return nil
}
func (r *mockFriendRepo) GetRequestByID(_ context.Context, _ string) (*domain.FriendRequest, error) {
	return nil, nil
}
func (r *mockFriendRepo) GetRequestsByReceiverID(_ context.Context, _ string) ([]*domain.FriendRequest, error) {
	return nil, nil
}
func (r *mockFriendRepo) GetRequestsBySenderID(_ context.Context, _ string) ([]*domain.FriendRequest, error) {
	return nil, nil
}
func (r *mockFriendRepo) UpdateRequestStatus(_ context.Context, _ string, _ domain.FriendRequestStatus) error {
	return nil
}
func (r *mockFriendRepo) AddFriend(_ context.Context, _, _ string) error { return nil }
func (r *mockFriendRepo) GetFriends(_ context.Context, _ string) ([]*domain.Friend, error) {
	return nil, nil
}
func (r *mockFriendRepo) RemoveFriend(_ context.Context, _, _ string) error { return nil }
func (r *mockFriendRepo) BlockUser(_ context.Context, _, _ string) error    { return nil }
func (r *mockFriendRepo) UnblockUser(_ context.Context, _, _ string) error  { return nil }
func (r *mockFriendRepo) IsBlocked(_ context.Context, _, _ string) (bool, error) {
	return false, nil
}
func (r *mockFriendRepo) GetBlockedUsers(_ context.Context, _ string) ([]*domain.Friend, error) {
	return nil, nil
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

var validPrivacyLevels = []domain.PrivacyLevel{
	domain.PrivacyLevelEveryone,
	domain.PrivacyLevelContacts,
	domain.PrivacyLevelNobody,
}

func drawValidLevel(t *rapid.T, label string) domain.PrivacyLevel {
	return rapid.SampledFrom(validPrivacyLevels).Draw(t, label)
}

// ---------------------------------------------------------------------------
// Property 1: Invalid PrivacyLevel Rejection
// Feature: privacy-settings, Property 1: Invalid PrivacyLevel Rejection
// ---------------------------------------------------------------------------

// Validates: Requirements 1.2, 1.5
func TestProperty1_InvalidPrivacyLevelRejected(t *testing.T) {
	rapid.Check(t, func(t *rapid.T) {
		invalidInt := rapid.Int().Filter(func(v int) bool { return v < 0 || v > 2 }).Draw(t, "invalidLevel")
		invalidLevel := domain.PrivacyLevel(invalidInt)

		privacyRepo := newMockPrivacyRepo()
		friendRepo := newMockFriendRepo(false)
		uc := NewPrivacySettingUsecase(privacyRepo, friendRepo)
		ctx := context.Background()

		initial := &domain.PrivacySetting{
			UserID:              "user1",
			LastSeenPrivacy:     domain.PrivacyLevelEveryone,
			OnlineStatusPrivacy: domain.PrivacyLevelEveryone,
			ProfilePhotoPrivacy: domain.PrivacyLevelEveryone,
			ReadReceiptsEnabled: true,
		}
		_ = privacyRepo.UpsertPrivacySetting(ctx, initial)

		req := domain.UpdatePrivacySettingRequest{
			LastSeenPrivacy: &invalidLevel,
		}
		_, err := uc.UpdatePrivacySetting(ctx, "user1", req)
		assert.Error(t, err)

		stored, _ := privacyRepo.GetPrivacySetting(ctx, "user1")
		assert.Equal(t, initial.LastSeenPrivacy, stored.LastSeenPrivacy)
		assert.Equal(t, initial.OnlineStatusPrivacy, stored.OnlineStatusPrivacy)
		assert.Equal(t, initial.ProfilePhotoPrivacy, stored.ProfilePhotoPrivacy)
		assert.Equal(t, initial.ReadReceiptsEnabled, stored.ReadReceiptsEnabled)
	})
}

// ---------------------------------------------------------------------------
// Property 2: Privacy Settings Update Round-Trip
// Feature: privacy-settings, Property 2: Privacy Settings Update Round-Trip
// ---------------------------------------------------------------------------

// Validates: Requirements 1.4, 6.2
func TestProperty2_UpdateRoundTrip(t *testing.T) {
	rapid.Check(t, func(t *rapid.T) {
		ls := drawValidLevel(t, "lastSeen")
		os := drawValidLevel(t, "onlineStatus")
		pp := drawValidLevel(t, "profilePhoto")
		rr := rapid.Bool().Draw(t, "readReceipts")

		privacyRepo := newMockPrivacyRepo()
		friendRepo := newMockFriendRepo(false)
		uc := NewPrivacySettingUsecase(privacyRepo, friendRepo)
		ctx := context.Background()

		req := domain.UpdatePrivacySettingRequest{
			LastSeenPrivacy:     &ls,
			OnlineStatusPrivacy: &os,
			ProfilePhotoPrivacy: &pp,
			ReadReceiptsEnabled: &rr,
		}

		updated, err := uc.UpdatePrivacySetting(ctx, "user1", req)
		assert.NoError(t, err)

		fetched, err := uc.GetPrivacySetting(ctx, "user1")
		assert.NoError(t, err)

		assert.Equal(t, updated.LastSeenPrivacy, fetched.LastSeenPrivacy)
		assert.Equal(t, updated.OnlineStatusPrivacy, fetched.OnlineStatusPrivacy)
		assert.Equal(t, updated.ProfilePhotoPrivacy, fetched.ProfilePhotoPrivacy)
		assert.Equal(t, updated.ReadReceiptsEnabled, fetched.ReadReceiptsEnabled)
	})
}

// ---------------------------------------------------------------------------
// Property 3: Partial Update Preserves Unspecified Fields
// Feature: privacy-settings, Property 3: Partial Update Preserves Unspecified Fields
// ---------------------------------------------------------------------------

// Validates: Requirements 6.4
func TestProperty3_PartialUpdatePreservesFields(t *testing.T) {
	rapid.Check(t, func(t *rapid.T) {
		initLS := drawValidLevel(t, "initLS")
		initOS := drawValidLevel(t, "initOS")
		initPP := drawValidLevel(t, "initPP")
		initRR := rapid.Bool().Draw(t, "initRR")

		updateLS := rapid.Bool().Draw(t, "updateLS")
		updateOS := rapid.Bool().Draw(t, "updateOS")
		updatePP := rapid.Bool().Draw(t, "updatePP")
		updateRR := rapid.Bool().Draw(t, "updateRR")

		if !updateLS && !updateOS && !updatePP && !updateRR {
			updateLS = true
		}

		privacyRepo := newMockPrivacyRepo()
		friendRepo := newMockFriendRepo(false)
		uc := NewPrivacySettingUsecase(privacyRepo, friendRepo)
		ctx := context.Background()

		initial := &domain.PrivacySetting{
			UserID:              "user1",
			LastSeenPrivacy:     initLS,
			OnlineStatusPrivacy: initOS,
			ProfilePhotoPrivacy: initPP,
			ReadReceiptsEnabled: initRR,
		}
		_ = privacyRepo.UpsertPrivacySetting(ctx, initial)

		req := domain.UpdatePrivacySettingRequest{}
		var newLS, newOS, newPP domain.PrivacyLevel
		var newRR bool

		if updateLS {
			newLS = drawValidLevel(t, "newLS")
			req.LastSeenPrivacy = &newLS
		}
		if updateOS {
			newOS = drawValidLevel(t, "newOS")
			req.OnlineStatusPrivacy = &newOS
		}
		if updatePP {
			newPP = drawValidLevel(t, "newPP")
			req.ProfilePhotoPrivacy = &newPP
		}
		if updateRR {
			newRR = rapid.Bool().Draw(t, "newRR")
			req.ReadReceiptsEnabled = &newRR
		}

		_, err := uc.UpdatePrivacySetting(ctx, "user1", req)
		assert.NoError(t, err)

		result, err := uc.GetPrivacySetting(ctx, "user1")
		assert.NoError(t, err)

		if updateLS {
			assert.Equal(t, newLS, result.LastSeenPrivacy)
		} else {
			assert.Equal(t, initLS, result.LastSeenPrivacy)
		}
		if updateOS {
			assert.Equal(t, newOS, result.OnlineStatusPrivacy)
		} else {
			assert.Equal(t, initOS, result.OnlineStatusPrivacy)
		}
		if updatePP {
			assert.Equal(t, newPP, result.ProfilePhotoPrivacy)
		} else {
			assert.Equal(t, initPP, result.ProfilePhotoPrivacy)
		}
		if updateRR {
			assert.Equal(t, newRR, result.ReadReceiptsEnabled)
		} else {
			assert.Equal(t, initRR, result.ReadReceiptsEnabled)
		}
	})
}

// ---------------------------------------------------------------------------
// Property 4: Presence Filtering Respects Subject's Privacy Level
// Feature: privacy-settings, Property 4: Presence Filtering Respects Subject's Privacy Level
// ---------------------------------------------------------------------------

// Validates: Requirements 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9
func TestProperty4_PresenceFilteringByPrivacyLevel(t *testing.T) {
	rapid.Check(t, func(t *rapid.T) {
		subjectLS := drawValidLevel(t, "subjectLS")
		subjectOS := drawValidLevel(t, "subjectOS")
		isFriend := rapid.Bool().Draw(t, "isFriend")
		realOnline := rapid.Bool().Draw(t, "realOnline")
		now := time.Now()
		realLastSeen := &now

		privacyRepo := newMockPrivacyRepo()
		friendRepo := newMockFriendRepo(isFriend)
		uc := NewPrivacySettingUsecase(privacyRepo, friendRepo)
		ctx := context.Background()

		viewerEveryone := domain.PrivacyLevelEveryone
		_ = privacyRepo.UpsertPrivacySetting(ctx, &domain.PrivacySetting{
			UserID:              "viewer",
			LastSeenPrivacy:     viewerEveryone,
			OnlineStatusPrivacy: viewerEveryone,
			ProfilePhotoPrivacy: viewerEveryone,
			ReadReceiptsEnabled: true,
		})
		_ = privacyRepo.UpsertPrivacySetting(ctx, &domain.PrivacySetting{
			UserID:              "subject",
			LastSeenPrivacy:     subjectLS,
			OnlineStatusPrivacy: subjectOS,
			ProfilePhotoPrivacy: domain.PrivacyLevelEveryone,
			ReadReceiptsEnabled: true,
		})

		subjects := map[string]*domain.PresenceInfo{
			"subject": {IsOnline: realOnline, LastSeen: realLastSeen},
		}

		result, err := uc.FilterPresence(ctx, "viewer", subjects)
		assert.NoError(t, err)

		filtered := result["subject"]
		assert.NotNil(t, filtered)

		effectiveOnlinePrivacy := subjectOS
		if effectiveOnlinePrivacy == domain.PrivacyLevelContacts && subjectLS == domain.PrivacyLevelNobody {
			effectiveOnlinePrivacy = domain.PrivacyLevelNobody
		}

		var expectedOnline bool
		switch effectiveOnlinePrivacy {
		case domain.PrivacyLevelNobody:
			expectedOnline = false
		case domain.PrivacyLevelContacts:
			expectedOnline = isFriend && realOnline
		case domain.PrivacyLevelEveryone:
			expectedOnline = realOnline
		}
		assert.Equal(t, expectedOnline, filtered.IsOnline)

		var expectedLastSeen *time.Time
		switch subjectLS {
		case domain.PrivacyLevelNobody:
			expectedLastSeen = nil
		case domain.PrivacyLevelContacts:
			if isFriend {
				expectedLastSeen = realLastSeen
			}
		case domain.PrivacyLevelEveryone:
			expectedLastSeen = realLastSeen
		}
		assert.Equal(t, expectedLastSeen, filtered.LastSeen)
	})
}

// ---------------------------------------------------------------------------
// Property 5: Reciprocity Rule for Presence
// Feature: privacy-settings, Property 5: Reciprocity Rule for Presence
// ---------------------------------------------------------------------------

// Validates: Requirements 2.10, 2.11
func TestProperty5_ReciprocityRule(t *testing.T) {
	rapid.Check(t, func(t *rapid.T) {
		viewerHidesLastSeen := rapid.Bool().Draw(t, "viewerHidesLastSeen")
		viewerHidesOnline := rapid.Bool().Draw(t, "viewerHidesOnline")
		if !viewerHidesLastSeen && !viewerHidesOnline {
			viewerHidesLastSeen = true
		}

		subjectLS := drawValidLevel(t, "subjectLS")
		subjectOS := drawValidLevel(t, "subjectOS")
		isFriend := rapid.Bool().Draw(t, "isFriend")
		realOnline := rapid.Bool().Draw(t, "realOnline")
		now := time.Now()
		realLastSeen := &now

		privacyRepo := newMockPrivacyRepo()
		friendRepo := newMockFriendRepo(isFriend)
		uc := NewPrivacySettingUsecase(privacyRepo, friendRepo)
		ctx := context.Background()

		viewerLS := domain.PrivacyLevelEveryone
		if viewerHidesLastSeen {
			viewerLS = domain.PrivacyLevelNobody
		}
		viewerOS := domain.PrivacyLevelEveryone
		if viewerHidesOnline {
			viewerOS = domain.PrivacyLevelNobody
		}

		_ = privacyRepo.UpsertPrivacySetting(ctx, &domain.PrivacySetting{
			UserID:              "viewer",
			LastSeenPrivacy:     viewerLS,
			OnlineStatusPrivacy: viewerOS,
			ProfilePhotoPrivacy: domain.PrivacyLevelEveryone,
			ReadReceiptsEnabled: true,
		})
		_ = privacyRepo.UpsertPrivacySetting(ctx, &domain.PrivacySetting{
			UserID:              "subject",
			LastSeenPrivacy:     subjectLS,
			OnlineStatusPrivacy: subjectOS,
			ProfilePhotoPrivacy: domain.PrivacyLevelEveryone,
			ReadReceiptsEnabled: true,
		})

		subjects := map[string]*domain.PresenceInfo{
			"subject": {IsOnline: realOnline, LastSeen: realLastSeen},
		}

		result, err := uc.FilterPresence(ctx, "viewer", subjects)
		assert.NoError(t, err)
		filtered := result["subject"]
		assert.NotNil(t, filtered)

		// Reciprocity: viewer with LastSeenPrivacy=Nobody cannot see last_seen when subject would otherwise show it.
		if viewerHidesLastSeen {
			if subjectLS == domain.PrivacyLevelEveryone {
				assert.Nil(t, filtered.LastSeen)
			}
			if subjectLS == domain.PrivacyLevelContacts && isFriend {
				assert.Nil(t, filtered.LastSeen)
			}
		}

		// Reciprocity: viewer with OnlineStatusPrivacy=Nobody cannot see is_online when subject would otherwise show it.
		if viewerHidesOnline {
			effectiveOnlinePrivacy := subjectOS
			if effectiveOnlinePrivacy == domain.PrivacyLevelContacts && subjectLS == domain.PrivacyLevelNobody {
				effectiveOnlinePrivacy = domain.PrivacyLevelNobody
			}
			if effectiveOnlinePrivacy == domain.PrivacyLevelEveryone {
				assert.False(t, filtered.IsOnline)
			}
			if effectiveOnlinePrivacy == domain.PrivacyLevelContacts && isFriend {
				assert.False(t, filtered.IsOnline)
			}
		}
	})
}

// ---------------------------------------------------------------------------
// Property 6: Online/LastSeen Linkage Rule
// Feature: privacy-settings, Property 6: Online/LastSeen Linkage Rule
// ---------------------------------------------------------------------------

// Validates: Requirements 3.1
func TestProperty6_OnlineLastSeenLinkageRule(t *testing.T) {
	rapid.Check(t, func(t *rapid.T) {
		isFriend := rapid.Bool().Draw(t, "isFriend")
		realOnline := rapid.Bool().Draw(t, "realOnline")
		now := time.Now()
		realLastSeen := &now

		privacyRepo := newMockPrivacyRepo()
		friendRepo := newMockFriendRepo(isFriend)
		uc := NewPrivacySettingUsecase(privacyRepo, friendRepo)
		ctx := context.Background()

		_ = privacyRepo.UpsertPrivacySetting(ctx, &domain.PrivacySetting{
			UserID:              "viewer",
			LastSeenPrivacy:     domain.PrivacyLevelEveryone,
			OnlineStatusPrivacy: domain.PrivacyLevelEveryone,
			ProfilePhotoPrivacy: domain.PrivacyLevelEveryone,
			ReadReceiptsEnabled: true,
		})
		// Subject: OnlineStatusPrivacy=Contacts AND LastSeenPrivacy=Nobody triggers linkage rule.
		_ = privacyRepo.UpsertPrivacySetting(ctx, &domain.PrivacySetting{
			UserID:              "subject",
			LastSeenPrivacy:     domain.PrivacyLevelNobody,
			OnlineStatusPrivacy: domain.PrivacyLevelContacts,
			ProfilePhotoPrivacy: domain.PrivacyLevelEveryone,
			ReadReceiptsEnabled: true,
		})

		subjects := map[string]*domain.PresenceInfo{
			"subject": {IsOnline: realOnline, LastSeen: realLastSeen},
		}

		result, err := uc.FilterPresence(ctx, "viewer", subjects)
		assert.NoError(t, err)

		filtered := result["subject"]
		assert.NotNil(t, filtered)

		// Linkage rule: is_online must be false for ALL viewers regardless of friendship.
		assert.False(t, filtered.IsOnline)
		// LastSeenPrivacy=Nobody means last_seen is always nil.
		assert.Nil(t, filtered.LastSeen)
	})
}

// ---------------------------------------------------------------------------
// Property 8: DM Read Receipt Mutual Suppression
// Feature: privacy-settings, Property 8: DM Read Receipt Mutual Suppression
// ---------------------------------------------------------------------------

// Validates: Requirements 5.1, 5.2
func TestProperty8_DMReadReceiptMutualSuppression(t *testing.T) {
	rapid.Check(t, func(t *rapid.T) {
		readerEnabled := rapid.Bool().Draw(t, "readerEnabled")
		senderEnabled := rapid.Bool().Draw(t, "senderEnabled")

		// Ensure at least one party has ReadReceiptsEnabled=false.
		if readerEnabled && senderEnabled {
			readerEnabled = false
		}

		privacyRepo := newMockPrivacyRepo()
		friendRepo := newMockFriendRepo(false)
		uc := NewPrivacySettingUsecase(privacyRepo, friendRepo)
		ctx := context.Background()

		_ = privacyRepo.UpsertPrivacySetting(ctx, &domain.PrivacySetting{
			UserID: "reader", ReadReceiptsEnabled: readerEnabled,
		})
		_ = privacyRepo.UpsertPrivacySetting(ctx, &domain.PrivacySetting{
			UserID: "sender", ReadReceiptsEnabled: senderEnabled,
		})

		// Direction A: reader reads sender's message.
		showAB, err := uc.ShouldShowReadReceipt(ctx, "reader", "sender", false)
		assert.NoError(t, err)
		assert.False(t, showAB)

		// Direction B: sender reads reader's message.
		showBA, err := uc.ShouldShowReadReceipt(ctx, "sender", "reader", false)
		assert.NoError(t, err)
		assert.False(t, showBA)
	})
}

// ---------------------------------------------------------------------------
// Property 9: Group Read Receipts Always Shown
// Feature: privacy-settings, Property 9: Group Read Receipts Always Shown
// ---------------------------------------------------------------------------

// Validates: Requirements 5.3
func TestProperty9_GroupReadReceiptsAlwaysShown(t *testing.T) {
	rapid.Check(t, func(t *rapid.T) {
		readerEnabled := rapid.Bool().Draw(t, "readerEnabled")
		senderEnabled := rapid.Bool().Draw(t, "senderEnabled")

		privacyRepo := newMockPrivacyRepo()
		friendRepo := newMockFriendRepo(false)
		uc := NewPrivacySettingUsecase(privacyRepo, friendRepo)
		ctx := context.Background()

		_ = privacyRepo.UpsertPrivacySetting(ctx, &domain.PrivacySetting{
			UserID: "reader", ReadReceiptsEnabled: readerEnabled,
		})
		_ = privacyRepo.UpsertPrivacySetting(ctx, &domain.PrivacySetting{
			UserID: "sender", ReadReceiptsEnabled: senderEnabled,
		})

		show, err := uc.ShouldShowReadReceipt(ctx, "reader", "sender", true)
		assert.NoError(t, err)
		assert.True(t, show)
	})
}
