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
	if !isImageContentType(contentType) {
		response.Error(c, http.StatusBadRequest, "invalid image type")
		return
	}

	ext := strings.ToLower(filepath.Ext(file.Filename))
	if ext == "" {
		ext = contentTypeToExt(contentType)
	}
	if ext == "" {
		response.Error(c, http.StatusBadRequest, "invalid image extension")
		return
	}

	fileName, err := generateFileName(ext)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "failed to generate filename")
		return
	}

	dir := filepath.Join(".", "uploads", "images")
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
		"url": "/uploads/images/" + fileName,
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
	default:
		return ""
	}
}
