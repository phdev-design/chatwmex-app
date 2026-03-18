package http

import (
	"bytes"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"chatwmex_backend/internal/config"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func setupMediaRouter(cfg *config.Config) *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	noAuth := func(c *gin.Context) { c.Next() }
	NewMediaHandler(r, noAuth, cfg)
	return r
}

// buildUploadRequest creates a multipart/form-data request with a minimal valid JPEG.
func buildUploadRequest(t *testing.T, filename string, content []byte) *http.Request {
	t.Helper()
	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)
	part, err := writer.CreateFormFile("file", filename)
	require.NoError(t, err)
	_, err = part.Write(content)
	require.NoError(t, err)
	require.NoError(t, writer.Close())

	req, err := http.NewRequest(http.MethodPost, "/api/v1/media/upload", body)
	require.NoError(t, err)
	req.Header.Set("Content-Type", writer.FormDataContentType())
	return req
}

// minimalJPEG returns the smallest valid JPEG header bytes so DetectContentType returns image/jpeg.
func minimalJPEG() []byte {
	return []byte{0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 'J', 'F', 'I', 'F', 0x00}
}

// minimalM4A returns bytes that trigger the audio/octet-stream + .m4a extension path.
func minimalM4A() []byte {
	// Not a real m4a, but enough to pass the extension check (octet-stream + .m4a ext)
	return []byte{0x00, 0x00, 0x00, 0x20, 'f', 't', 'y', 'p'}
}

// TestUploadImage_ReturnsAbsoluteURL_WithStorageBaseURL verifies that when
// STORAGE_BASE_URL is configured, the returned URL is absolute (not a relative path).
func TestUploadImage_ReturnsAbsoluteURL_WithStorageBaseURL(t *testing.T) {
	cfg := &config.Config{
		StorageBaseURL: "https://api-chat2mex.phdev.uk",
	}
	r := setupMediaRouter(cfg)

	req := buildUploadRequest(t, "test.jpg", minimalJPEG())
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	require.Equal(t, http.StatusOK, w.Code)

	body := w.Body.String()
	assert.True(t,
		strings.Contains(body, "https://api-chat2mex.phdev.uk/uploads/images/"),
		"expected absolute URL with base, got: %s", body,
	)
	assert.False(t,
		strings.HasPrefix(extractURL(body), "/uploads/"),
		"URL must not be a relative path, got: %s", body,
	)
}

// TestUploadImage_ReturnsAbsoluteURL_StorageBaseURLWithUploads verifies that if
// STORAGE_BASE_URL already contains "/uploads" suffix it is not doubled.
func TestUploadImage_ReturnsAbsoluteURL_StorageBaseURLWithUploads(t *testing.T) {
	cfg := &config.Config{
		StorageBaseURL: "https://api-chat2mex.phdev.uk/uploads", // trailing /uploads
	}
	r := setupMediaRouter(cfg)

	req := buildUploadRequest(t, "test.jpg", minimalJPEG())
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	require.Equal(t, http.StatusOK, w.Code)

	url := extractURL(w.Body.String())
	assert.True(t,
		strings.HasPrefix(url, "https://api-chat2mex.phdev.uk/uploads/images/"),
		"expected no double /uploads, got: %s", url,
	)
	assert.False(t,
		strings.Contains(url, "/uploads/uploads/"),
		"URL must not contain double /uploads, got: %s", url,
	)
}

// TestUploadImage_ReturnsRelativeURL_WhenNoStorageBaseURL verifies backward-compat:
// if STORAGE_BASE_URL is empty the handler still returns a path (relative).
func TestUploadImage_ReturnsRelativeURL_WhenNoStorageBaseURL(t *testing.T) {
	cfg := &config.Config{StorageBaseURL: ""}
	r := setupMediaRouter(cfg)

	req := buildUploadRequest(t, "test.jpg", minimalJPEG())
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	require.Equal(t, http.StatusOK, w.Code)

	url := extractURL(w.Body.String())
	assert.True(t,
		strings.HasPrefix(url, "/uploads/images/"),
		"expected relative path fallback, got: %s", url,
	)
}

// TestUploadAudio_ReturnsAbsoluteURL verifies audio files also get absolute URLs.
func TestUploadAudio_ReturnsAbsoluteURL(t *testing.T) {
	cfg := &config.Config{
		StorageBaseURL: "https://api-chat2mex.phdev.uk",
	}
	r := setupMediaRouter(cfg)

	req := buildUploadRequest(t, "voice.m4a", minimalM4A())
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	require.Equal(t, http.StatusOK, w.Code)

	url := extractURL(w.Body.String())
	assert.True(t,
		strings.HasPrefix(url, "https://api-chat2mex.phdev.uk/uploads/audio/"),
		"expected absolute audio URL, got: %s", url,
	)
}

// extractURL pulls the "url" value from the JSON response body.
func extractURL(body string) string {
	// Simple extraction: find `"url":"<value>"`
	const key = `"url":"`
	idx := strings.Index(body, key)
	if idx == -1 {
		return ""
	}
	rest := body[idx+len(key):]
	end := strings.Index(rest, `"`)
	if end == -1 {
		return rest
	}
	return rest[:end]
}
