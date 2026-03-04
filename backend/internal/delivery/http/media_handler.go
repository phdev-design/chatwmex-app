package http

import (
	"crypto/rand"
	"encoding/hex"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"chatwmex_backend/pkg/response"

	"github.com/gin-gonic/gin"
)

type MediaHandler struct{}

func NewMediaHandler(r *gin.Engine, authMiddleware gin.HandlerFunc) {
	handler := &MediaHandler{}

	api := r.Group("/api/v1/media")
	api.Use(authMiddleware)
	{
		api.POST("/upload", handler.UploadImage)
	}
}

func (h *MediaHandler) UploadImage(c *gin.Context) {
	file, err := c.FormFile("file")
	if err != nil {
		response.Error(c, http.StatusBadRequest, "file is required")
		return
	}

	const maxSize = 5 * 1024 * 1024
	if file.Size > maxSize {
		response.Error(c, http.StatusBadRequest, "file size exceeds 5MB")
		return
	}

	src, err := file.Open()
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "failed to open file")
		return
	}
	defer src.Close()

	buffer := make([]byte, 512)
	n, _ := src.Read(buffer)
	contentType := http.DetectContentType(buffer[:n])
	isImage := isImageContentType(contentType)
	isAudio := isAudioContentType(contentType)
	if !isImage && !isAudio {
		response.Error(c, http.StatusBadRequest, "invalid media type")
		return
	}

	ext := strings.ToLower(filepath.Ext(file.Filename))
	if ext == "" {
		ext = contentTypeToExt(contentType)
	}
	if ext == "" {
		response.Error(c, http.StatusBadRequest, "invalid media extension")
		return
	}
	if !isAllowedMediaExt(ext) {
		response.Error(c, http.StatusBadRequest, "unsupported media extension")
		return
	}

	fileName, err := generateFileName(ext)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "failed to generate filename")
		return
	}

	dirType := "images"
	if isAudio {
		dirType = "audio"
	}
	dir := filepath.Join(uploadsRootDir, dirType)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		response.Error(c, http.StatusInternalServerError, "failed to create upload directory")
		return
	}

	dstPath := filepath.Join(dir, fileName)
	if err := c.SaveUploadedFile(file, dstPath); err != nil {
		response.Error(c, http.StatusInternalServerError, "failed to save file")
		return
	}

	response.Success(c, gin.H{
		"url": "/uploads/" + dirType + "/" + fileName,
	})
}

func generateFileName(ext string) (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b) + ext, nil
}

func isImageContentType(contentType string) bool {
	switch contentType {
	case "image/jpeg", "image/png", "image/gif", "image/webp":
		return true
	default:
		return false
	}
}

func isAudioContentType(contentType string) bool {
	switch contentType {
	case "audio/mp4", "audio/aac", "audio/mpeg", "audio/x-m4a":
		return true
	default:
		return false
	}
}

func isAllowedMediaExt(ext string) bool {
	switch ext {
	case ".jpg", ".jpeg", ".png", ".gif", ".webp", ".m4a", ".mp3", ".aac":
		return true
	default:
		return false
	}
}

func contentTypeToExt(contentType string) string {
	switch contentType {
	case "image/jpeg":
		return ".jpg"
	case "image/png":
		return ".png"
	case "image/gif":
		return ".gif"
	case "image/webp":
		return ".webp"
	case "audio/mp4", "audio/x-m4a":
		return ".m4a"
	case "audio/aac":
		return ".aac"
	case "audio/mpeg":
		return ".mp3"
	default:
		return ""
	}
}
