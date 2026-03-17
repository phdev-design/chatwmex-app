package http

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"chatwmex_backend/internal/delivery/http/middleware"
	"chatwmex_backend/internal/domain"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"pgregory.net/rapid"
)

// --- Mock usecase ---

type mockPrivacySettingUsecase struct {
	getSetting    func(ctx context.Context, userID string) (*domain.PrivacySetting, error)
	updateSetting func(ctx context.Context, userID string, req domain.UpdatePrivacySettingRequest) (*domain.PrivacySetting, error)
}

func (m *mockPrivacySettingUsecase) GetPrivacySetting(ctx context.Context, userID string) (*domain.PrivacySetting, error) {
	return m.getSetting(ctx, userID)
}

func (m *mockPrivacySettingUsecase) UpdatePrivacySetting(ctx context.Context, userID string, req domain.UpdatePrivacySettingRequest) (*domain.PrivacySetting, error) {
	return m.updateSetting(ctx, userID, req)
}

func (m *mockPrivacySettingUsecase) FilterPresence(ctx context.Context, viewerID string, subjects map[string]*domain.PresenceInfo) (map[string]*domain.PresenceInfo, error) {
	return subjects, nil
}

func (m *mockPrivacySettingUsecase) ShouldShowReadReceipt(ctx context.Context, readerID, senderID string, isGroup bool) (bool, error) {
	return true, nil
}

// --- Test helpers ---

// noAuthMiddleware is a no-op middleware that does NOT set the userID in context.
func noAuthMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Next()
	}
}

// fakeAuthMiddleware sets a fixed userID in context, simulating a valid JWT.
func fakeAuthMiddleware(userID string) gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Set(middleware.ContextUserIDKey, userID)
		c.Next()
	}
}

func setupRouter(usecase domain.PrivacySettingUsecase, authMiddleware gin.HandlerFunc) *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	NewPrivacySettingHandler(r, usecase, authMiddleware)
	return r
}

// --- Unit Tests ---

// TestPrivacySettingHandler_GET_Unauthorized verifies that a GET request without
// a valid JWT (no userID in context) returns HTTP 401.
// Requirements: 6.3
func TestPrivacySettingHandler_GET_Unauthorized(t *testing.T) {
	uc := &mockPrivacySettingUsecase{}
	r := setupRouter(uc, noAuthMiddleware())

	req := httptest.NewRequest(http.MethodGet, "/api/v1/privacy-settings", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	assert.Equal(t, http.StatusUnauthorized, w.Code)
}

// TestPrivacySettingHandler_GET_Success verifies that a GET request with a valid
// JWT returns HTTP 200 and the PrivacySetting JSON.
// Requirements: 6.1, 6.2
func TestPrivacySettingHandler_GET_Success(t *testing.T) {
	expected := &domain.PrivacySetting{
		UserID:              "user-123",
		LastSeenPrivacy:     domain.PrivacyLevelEveryone,
		OnlineStatusPrivacy: domain.PrivacyLevelContacts,
		ProfilePhotoPrivacy: domain.PrivacyLevelNobody,
		ReadReceiptsEnabled: true,
	}

	uc := &mockPrivacySettingUsecase{
		getSetting: func(_ context.Context, userID string) (*domain.PrivacySetting, error) {
			return expected, nil
		},
	}
	r := setupRouter(uc, fakeAuthMiddleware("user-123"))

	req := httptest.NewRequest(http.MethodGet, "/api/v1/privacy-settings", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)

	var resp map[string]interface{}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
	data, ok := resp["data"].(map[string]interface{})
	require.True(t, ok)
	assert.Equal(t, "user-123", data["user_id"])
}

// TestPrivacySettingHandler_PUT_Success verifies that a PUT request with a valid
// update body returns HTTP 200 and the updated PrivacySetting JSON.
// Requirements: 6.1, 6.2, 6.4
func TestPrivacySettingHandler_PUT_Success(t *testing.T) {
	level := domain.PrivacyLevelContacts
	enabled := false
	updated := &domain.PrivacySetting{
		UserID:              "user-123",
		LastSeenPrivacy:     level,
		OnlineStatusPrivacy: domain.PrivacyLevelEveryone,
		ProfilePhotoPrivacy: domain.PrivacyLevelEveryone,
		ReadReceiptsEnabled: enabled,
	}

	uc := &mockPrivacySettingUsecase{
		updateSetting: func(_ context.Context, userID string, req domain.UpdatePrivacySettingRequest) (*domain.PrivacySetting, error) {
			return updated, nil
		},
	}
	r := setupRouter(uc, fakeAuthMiddleware("user-123"))

	body, _ := json.Marshal(domain.UpdatePrivacySettingRequest{
		LastSeenPrivacy:     &level,
		ReadReceiptsEnabled: &enabled,
	})
	req := httptest.NewRequest(http.MethodPut, "/api/v1/privacy-settings", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)

	var resp map[string]interface{}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
	data, ok := resp["data"].(map[string]interface{})
	require.True(t, ok)
	assert.Equal(t, float64(1), data["last_seen_privacy"])
	assert.Equal(t, false, data["read_receipts_enabled"])
}

// TestPrivacySettingHandler_PUT_InvalidLevel verifies that a PUT request with an
// invalid PrivacyLevel value returns HTTP 400.
// Requirements: 6.3
func TestPrivacySettingHandler_PUT_InvalidLevel(t *testing.T) {
	uc := &mockPrivacySettingUsecase{
		updateSetting: func(_ context.Context, userID string, req domain.UpdatePrivacySettingRequest) (*domain.PrivacySetting, error) {
			return nil, &invalidPrivacyLevelError{msg: "invalid privacy level: 99"}
		},
	}
	r := setupRouter(uc, fakeAuthMiddleware("user-123"))

	// Send a raw JSON with an out-of-range level value
	body := []byte(`{"last_seen_privacy": 99}`)
	req := httptest.NewRequest(http.MethodPut, "/api/v1/privacy-settings", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	assert.Equal(t, http.StatusBadRequest, w.Code)
}

// invalidPrivacyLevelError is a helper error type that contains "invalid privacy level"
// so the handler maps it to HTTP 400.
type invalidPrivacyLevelError struct{ msg string }

func (e *invalidPrivacyLevelError) Error() string { return e.msg }

// --- Property-Based Test ---

// Feature: privacy-settings, Property 10: Unauthenticated Requests Rejected
//
// For any request to GET /api/v1/privacy-settings or PUT /api/v1/privacy-settings
// that does not carry a valid JWT Bearer token, the server SHALL respond with HTTP 401.
//
// Validates: Requirements 6.3
func TestProperty10_UnauthenticatedRequestsRejected(t *testing.T) {
	uc := &mockPrivacySettingUsecase{}
	// Use noAuthMiddleware so no userID is ever set in context.
	r := setupRouter(uc, noAuthMiddleware())

	rapid.Check(t, func(rt *rapid.T) {
		// Generate an arbitrary JSON body (may be empty, valid JSON, or random bytes).
		bodyStr := rapid.StringMatching(`.*`).Draw(rt, "body")
		bodyBytes := []byte(bodyStr)

		// Test GET
		getReq := httptest.NewRequest(http.MethodGet, "/api/v1/privacy-settings", nil)
		getW := httptest.NewRecorder()
		r.ServeHTTP(getW, getReq)
		if getW.Code != http.StatusUnauthorized {
			rt.Fatalf("GET expected 401, got %d", getW.Code)
		}

		// Test PUT with arbitrary body
		putReq := httptest.NewRequest(http.MethodPut, "/api/v1/privacy-settings", bytes.NewReader(bodyBytes))
		putReq.Header.Set("Content-Type", "application/json")
		putW := httptest.NewRecorder()
		r.ServeHTTP(putW, putReq)
		if putW.Code != http.StatusUnauthorized {
			rt.Fatalf("PUT expected 401, got %d (body: %q)", putW.Code, bodyStr)
		}
	})
}
