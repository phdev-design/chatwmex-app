package controllers

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"path/filepath"
	"strings"
	"time"

	"chatwme/backend/config"
	"chatwme/backend/database"
	"chatwme/backend/middleware"
	"chatwme/backend/models"
	"chatwme/backend/services"
	"chatwme/backend/utils"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
)

// AvatarUploadResponse 頭像上傳響應結構
type AvatarUploadResponse struct {
	Message   string `json:"message"`
	AvatarURL string `json:"avatar_url"`
}

// UploadAvatar 上傳用戶頭像
func UploadAvatar(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	// 從 JWT 中獲取用戶 ID
	userID, ok := r.Context().Value(middleware.UserIDKey).(string)
	if !ok {
		http.Error(w, `{"error": "無法獲取用戶 ID"}`, http.StatusUnauthorized)
		return
	}

	// 檢查請求方法
	if r.Method != http.MethodPost {
		http.Error(w, `{"error": "只允許 POST 請求"}`, http.StatusMethodNotAllowed)
		return
	}

	// 解析 multipart form，限制文件大小為 5MB
	err := r.ParseMultipartForm(5 << 20) // 5MB
	if err != nil {
		log.Printf("解析 multipart form 失敗: %v", err)
		http.Error(w, `{"error": "文件太大或格式不正確"}`, http.StatusBadRequest)
		return
	}

	// 獲取上傳的文件
	file, header, err := r.FormFile("avatar")
	if err != nil {
		log.Printf("獲取上傳文件失敗: %v", err)
		http.Error(w, `{"error": "未找到上傳文件"}`, http.StatusBadRequest)
		return
	}
	defer file.Close()

	// 🔥 修復：驗證文件類型（改進類型檢查）
	allowedTypes := []string{"image/jpeg", "image/jpg", "image/png", "image/gif", "image/webp"}
	contentType := header.Header.Get("Content-Type")

	// 添加調試信息
	log.Printf("收到文件 - 文件名: %s, Content-Type: %s, 大小: %d",
		header.Filename, contentType, header.Size)

	if !isAllowedImageType(contentType, allowedTypes) {
		log.Printf("文件類型檢查失敗 - Content-Type: %s, 允許的類型: %v", contentType, allowedTypes)
		http.Error(w, `{"error": "不支持的文件類型，請上傳 JPEG、PNG、GIF 或 WebP 格式的圖片"}`, http.StatusBadRequest)
		return
	}

	// 驗證文件大小
	if header.Size > 5*1024*1024 { // 5MB
		http.Error(w, `{"error": "文件大小不能超過 5MB"}`, http.StatusBadRequest)
		return
	}

	// 驗證文件擴展名
	ext := strings.ToLower(filepath.Ext(header.Filename))
	allowedExts := []string{".jpg", ".jpeg", ".png", ".gif", ".webp"}
	if !isAllowedExtension(ext, allowedExts) {
		http.Error(w, `{"error": "不支持的文件擴展名"}`, http.StatusBadRequest)
		return
	}

	log.Printf("收到頭像上傳請求 - UserID: %s, 文件名: %s, 大小: %d bytes",
		userID, header.Filename, header.Size)

	// 獲取數據庫連接
	cfg := config.LoadConfig()
	userCollection := database.GetCollection("users", cfg.MongoDbName)
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// 將字符串 ID 轉換為 ObjectID
	objectID, err := primitive.ObjectIDFromHex(userID)
	if err != nil {
		http.Error(w, `{"error": "無效的用戶 ID"}`, http.StatusBadRequest)
		return
	}

	// 查找用戶
	var user models.User
	err = userCollection.FindOne(ctx, bson.M{"_id": objectID}).Decode(&user)
	if err != nil {
		if err == mongo.ErrNoDocuments {
			http.Error(w, `{"error": "用戶不存在"}`, http.StatusNotFound)
		} else {
			log.Printf("查找用戶時發生錯誤: %v", err)
			http.Error(w, `{"error": "查找用戶時發生錯誤"}`, http.StatusInternalServerError)
		}
		return
	}

	// 使用全局存儲服務實例
	storageService := services.GetStorageService()

	// 上傳文件
	filePath, err := storageService.UploadFile(file, header, "avatars")
	if err != nil {
		log.Printf("上傳頭像失敗: %v", err)
		http.Error(w, `{"error": "上傳頭像失敗"}`, http.StatusInternalServerError)
		return
	}

	// 生成公共 URL
	avatarURL := storageService.GetPublicURL(filePath)

	// 刪除舊頭像（如果存在）
	if user.AvatarURL != nil && *user.AvatarURL != "" {
		oldFilePath := utils.ExtractFilePathFromURL(*user.AvatarURL)
		if oldFilePath != "" {
			if err := storageService.DeleteFile(oldFilePath); err != nil {
				log.Printf("刪除舊頭像失敗: %v", err)
				// 不返回錯誤，繼續更新數據庫
			}
		}
	}

	// 更新用戶頭像 URL
	updateResult, err := userCollection.UpdateOne(
		ctx,
		bson.M{"_id": objectID},
		bson.M{
			"$set": bson.M{
				"avatar_url": avatarURL,
				"updated_at": time.Now(),
			},
		},
	)
	if err != nil {
		log.Printf("更新用戶頭像失敗: %v", err)
		// 如果數據庫更新失敗，刪除已上傳的文件
		storageService.DeleteFile(filePath)
		http.Error(w, `{"error": "更新用戶頭像失敗"}`, http.StatusInternalServerError)
		return
	}

	if updateResult.MatchedCount == 0 {
		// 如果數據庫更新失敗，刪除已上傳的文件
		storageService.DeleteFile(filePath)
		http.Error(w, `{"error": "用戶不存在"}`, http.StatusNotFound)
		return
	}

	log.Printf("用戶頭像上傳成功 - UserID: %s, AvatarURL: %s", userID, avatarURL)

	// 返回成功響應
	response := AvatarUploadResponse{
		Message:   "頭像上傳成功",
		AvatarURL: avatarURL,
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}

// DeleteAvatar 刪除用戶頭像
func DeleteAvatar(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	// 從 JWT 中獲取用戶 ID
	userID, ok := r.Context().Value(middleware.UserIDKey).(string)
	if !ok {
		http.Error(w, `{"error": "無法獲取用戶 ID"}`, http.StatusUnauthorized)
		return
	}

	// 檢查請求方法
	if r.Method != http.MethodDelete {
		http.Error(w, `{"error": "只允許 DELETE 請求"}`, http.StatusMethodNotAllowed)
		return
	}

	log.Printf("收到刪除頭像請求 - UserID: %s", userID)

	// 獲取數據庫連接
	cfg := config.LoadConfig()
	userCollection := database.GetCollection("users", cfg.MongoDbName)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// 將字符串 ID 轉換為 ObjectID
	objectID, err := primitive.ObjectIDFromHex(userID)
	if err != nil {
		http.Error(w, `{"error": "無效的用戶 ID"}`, http.StatusBadRequest)
		return
	}

	// 查找用戶
	var user models.User
	err = userCollection.FindOne(ctx, bson.M{"_id": objectID}).Decode(&user)
	if err != nil {
		if err == mongo.ErrNoDocuments {
			http.Error(w, `{"error": "用戶不存在"}`, http.StatusNotFound)
		} else {
			log.Printf("查找用戶時發生錯誤: %v", err)
			http.Error(w, `{"error": "查找用戶時發生錯誤"}`, http.StatusInternalServerError)
		}
		return
	}

	// 檢查用戶是否有頭像
	if user.AvatarURL == nil || *user.AvatarURL == "" {
		http.Error(w, `{"error": "用戶沒有頭像"}`, http.StatusNotFound)
		return
	}

	// 使用全局存儲服務實例
	storageService := services.GetStorageService()
	filePath := utils.ExtractFilePathFromURL(*user.AvatarURL)
	if filePath != "" {
		if err := storageService.DeleteFile(filePath); err != nil {
			log.Printf("刪除頭像文件失敗: %v", err)
			// 不返回錯誤，繼續更新數據庫
		}
	}

	// 更新數據庫，清空頭像 URL
	updateResult, err := userCollection.UpdateOne(
		ctx,
		bson.M{"_id": objectID},
		bson.M{
			"$unset": bson.M{"avatar_url": ""},
			"$set":   bson.M{"updated_at": time.Now()},
		},
	)
	if err != nil {
		log.Printf("更新用戶頭像失敗: %v", err)
		http.Error(w, `{"error": "刪除頭像失敗"}`, http.StatusInternalServerError)
		return
	}

	if updateResult.MatchedCount == 0 {
		http.Error(w, `{"error": "用戶不存在"}`, http.StatusNotFound)
		return
	}

	log.Printf("用戶頭像刪除成功 - UserID: %s", userID)

	// 返回成功響應
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{
		"message": "頭像刪除成功",
	})
}

// 🔥 修復：isAllowedImageType 檢查是否為允許的圖片類型（改進類型檢查）
func isAllowedImageType(contentType string, allowedTypes []string) bool {
	// 如果 Content-Type 為空，嘗試從文件擴展名判斷
	if contentType == "" {
		log.Printf("Content-Type 為空，跳過類型檢查")
		return true
	}

	// 標準檢查
	for _, allowedType := range allowedTypes {
		if contentType == allowedType {
			return true
		}
	}

	// 🔥 新增：更寬鬆的檢查，支持常見的變體
	contentTypeLower := strings.ToLower(contentType)
	if strings.Contains(contentTypeLower, "image/jpeg") ||
		strings.Contains(contentTypeLower, "image/jpg") ||
		strings.Contains(contentTypeLower, "image/png") ||
		strings.Contains(contentTypeLower, "image/gif") ||
		strings.Contains(contentTypeLower, "image/webp") {
		return true
	}

	return false
}

// isAllowedExtension 檢查是否為允許的文件擴展名
func isAllowedExtension(ext string, allowedExts []string) bool {
	for _, allowedExt := range allowedExts {
		if ext == allowedExt {
			return true
		}
	}
	return false
}
