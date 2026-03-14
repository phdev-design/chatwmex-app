package http

import (
	"os"
	"path/filepath"
)

var uploadsRootDir = getUploadsRootDir()

func getUploadsRootDir() string {
	// Try "uploads" first (when running from cmd/server)
	dir := "uploads"
	if _, err := os.Stat(dir); err == nil {
		return dir
	}
	// Fall back to "cmd/server/uploads" (when running from backend root)
	return filepath.Join("cmd", "server", "uploads")
}
