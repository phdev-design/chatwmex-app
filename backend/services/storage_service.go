package services

import (
	"fmt"
	"io"
	"log"
	"mime/multipart"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

// StorageService 抽象存儲接口
type StorageService interface {
	UploadFile(file multipart.File, header *multipart.FileHeader, category string) (string, error)
	GetPublicURL(filePath string) string
	DeleteFile(filePath string) error
	GetFileSize(filePath string) (int64, error)
}

// LocalStorageService 本地文件存儲實現
type LocalStorageService struct {
	BaseURL    string
	UploadPath string
}

// 全局存儲服務實例
var (
	storageServiceInstance *LocalStorageService
	storageServiceOnce     sync.Once
)

// NewLocalStorageService 創建新的本地存儲服務
func NewLocalStorageService() *LocalStorageService {
	// 使用統一的環境配置
	baseURL := os.Getenv("STORAGE_BASE_URL")
	if baseURL == "" {
		// 自動檢測環境
		environment := os.Getenv("ENVIRONMENT")
		if environment == "" {
			if os.Getenv("USE_CLOUDFLARE") == "true" {
				environment = "production"
			} else {
				environment = "development"
			}
		}

		if environment == "production" {
			baseURL = "https://api-chatwmex.phdev.uk/uploads"
			log.Printf("🌐 Using production Cloudflare URL for storage: %s", baseURL)
		} else {
			// 開發環境，支援多種測試主機
			testHost := os.Getenv("TEST_HOST")
			if testHost == "" {
				testHost = "192.168.100.111:8080" // 預設本地測試
			}
			baseURL = "http://" + testHost + "/uploads"
			log.Printf("🚢 Using development URL for storage: %s", baseURL)
		}
	}

	uploadPath := os.Getenv("UPLOAD_PATH")
	if uploadPath == "" {
		uploadPath = "./uploads"
	}

	service := &LocalStorageService{
		BaseURL:    baseURL,
		UploadPath: uploadPath,
	}

	log.Printf("🎵 LocalStorageService initialized:")
	log.Printf("   BaseURL: %s", baseURL)
	log.Printf("   UploadPath: %s", uploadPath)
	log.Printf("   Environment: %s", getEnvironment())

	return service
}

// GetStorageService 獲取全局存儲服務實例（單例模式）
func GetStorageService() *LocalStorageService {
	storageServiceOnce.Do(func() {
		storageServiceInstance = NewLocalStorageService()
	})
	return storageServiceInstance
}

// getEnvironment 获取当前环境信息
func getEnvironment() string {
	if env := os.Getenv("ENVIRONMENT"); env != "" {
		return env
	}
	if os.Getenv("USE_CLOUDFLARE") == "true" {
		return "production-cloudflare"
	}
	return "development"
}

// UploadFile 上傳文件到本地存儲
func (s *LocalStorageService) UploadFile(file multipart.File, header *multipart.FileHeader, category string) (string, error) {
	// 創建基於日期的目錄結構
	now := time.Now()
	dateDir := fmt.Sprintf("%d/%02d/%02d", now.Year(), now.Month(), now.Day())

	// 構建完整的目錄路徑
	fullDir := filepath.Join(s.UploadPath, category, dateDir)

	// 確保目錄存在
	if err := os.MkdirAll(fullDir, 0755); err != nil {
		log.Printf("❌ Failed to create directory %s: %v", fullDir, err)
		return "", fmt.Errorf("failed to create directory: %v", err)
	}

	// 生成唯一的文件名
	ext := filepath.Ext(header.Filename)
	fileName := fmt.Sprintf("%d_%s%s", now.UnixNano(), generateRandomString(8), ext)

	// 構建相對路徑（這個會存儲在數據庫中）
	relativePath := filepath.Join(category, dateDir, fileName)

	// 構建完整的文件路徑
	fullPath := filepath.Join(s.UploadPath, relativePath)

	log.Printf("📁 Uploading file:")
	log.Printf("   Original: %s (size: %d)", header.Filename, header.Size)
	log.Printf("   Target: %s", fullPath)

	// 創建目標文件
	dst, err := os.Create(fullPath)
	if err != nil {
		log.Printf("❌ Failed to create file %s: %v", fullPath, err)
		return "", fmt.Errorf("failed to create file: %v", err)
	}
	defer dst.Close()

	// 復制文件內容
	written, err := io.Copy(dst, file)
	if err != nil {
		log.Printf("❌ Failed to save file %s: %v", fullPath, err)
		return "", fmt.Errorf("failed to save file: %v", err)
	}

	// 返回相對路徑（用斜杠分隔，便於未來遷移到S3）
	normalizedPath := strings.ReplaceAll(relativePath, "\\", "/")
	log.Printf("✅ File uploaded successfully:")
	log.Printf("   Written: %d bytes", written)
	log.Printf("   Relative path: %s", normalizedPath)

	return normalizedPath, nil
}

// GetPublicURL 獲取文件的公共訪問URL
func (s *LocalStorageService) GetPublicURL(filePath string) string {
	// 🔥 修正：确保路径格式正确
	normalizedPath := strings.ReplaceAll(filePath, "\\", "/")
	publicURL := fmt.Sprintf("%s/%s", strings.TrimRight(s.BaseURL, "/"), strings.TrimLeft(normalizedPath, "/"))

	log.Printf("🌐 Generated public URL: %s", publicURL)
	log.Printf("   From file path: %s", filePath)
	log.Printf("   Base URL: %s", s.BaseURL)

	return publicURL
}

// DeleteFile 刪除文件
func (s *LocalStorageService) DeleteFile(filePath string) error {
	fullPath := filepath.Join(s.UploadPath, filePath)

	log.Printf("🗑️  Attempting to delete file: %s", fullPath)

	err := os.Remove(fullPath)
	if err != nil {
		log.Printf("❌ Error deleting file %s: %v", fullPath, err)
		return err
	}
	log.Printf("✅ File deleted successfully: %s", fullPath)
	return nil
}

// GetFileSize 獲取文件大小
func (s *LocalStorageService) GetFileSize(filePath string) (int64, error) {
	fullPath := filepath.Join(s.UploadPath, filePath)

	log.Printf("📏 Getting file size for: %s", fullPath)
	log.Printf("   UploadPath: %s", s.UploadPath)
	log.Printf("   FilePath: %s", filePath)
	log.Printf("   FullPath: %s", fullPath)

	// 檢查文件是否存在
	if _, err := os.Stat(fullPath); os.IsNotExist(err) {
		log.Printf("❌ File does not exist: %s", fullPath)
		return 0, fmt.Errorf("file does not exist: %s", fullPath)
	}

	fileInfo, err := os.Stat(fullPath)
	if err != nil {
		log.Printf("❌ Error getting file size for %s: %v", fullPath, err)
		return 0, err
	}

	size := fileInfo.Size()
	log.Printf("✅ File size: %d bytes (%.2f KB)", size, float64(size)/1024.0)

	// 驗證文件大小是否合理
	if size <= 0 {
		log.Printf("⚠️  Warning: File size is 0 or negative: %d bytes", size)
	}

	return size, nil
}

// generateRandomString 生成隨機字符串
func generateRandomString(length int) string {
	const charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	result := make([]byte, length)
	for i := range result {
		result[i] = charset[time.Now().UnixNano()%int64(len(charset))]
	}
	return string(result)
}

// UploadAvatar 專門用於上傳頭像的便捷方法
func (s *LocalStorageService) UploadAvatar(file multipart.File, header *multipart.FileHeader) (string, error) {
	return s.UploadFile(file, header, "avatars")
}

// GetAvatarURL 獲取頭像的公共 URL
func (s *LocalStorageService) GetAvatarURL(filePath string) string {
	return s.GetPublicURL(filePath)
}
