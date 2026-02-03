package controllers

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"chatwme/backend/config"
	"chatwme/backend/middleware"
	"chatwme/backend/models"
	"chatwme/backend/services"
	"chatwme/backend/utils"

	"github.com/gorilla/mux"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
)

// VoiceMessageResponse 語音消息響應結構
type VoiceMessageResponse struct {
	ID         string `json:"id"`
	SenderID   string `json:"sender_id"`
	SenderName string `json:"sender_name"`
	Room       string `json:"room"`
	FileURL    string `json:"file_url"`
	Duration   int    `json:"duration"`  // 語音時長，秒
	FileSize   int64  `json:"file_size"` // 文件大小，字節
	Timestamp  string `json:"timestamp"`
	Type       string `json:"type"`
}

var storageService services.StorageService

func init() {
	// 初始化存儲服務（使用單例模式）
	storageService = services.GetStorageService()
}

// UploadVoiceMessage 處理語音消息上傳 - 🔥 統一存儲到 messages 集合
func UploadVoiceMessage(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	// 從 JWT 中獲取用戶 ID
	userID, ok := r.Context().Value(middleware.UserIDKey).(string)
	if !ok {
		http.Error(w, `{"error": "無法獲取用戶 ID"}`, http.StatusUnauthorized)
		return
	}

	store, ok := getStore(r)
	if !ok {
		http.Error(w, `{"error": "資料庫尚未初始化"}`, http.StatusInternalServerError)
		return
	}

	// 從 URL 參數中獲取房間 ID
	params := mux.Vars(r)
	roomID := params["id"]
	if roomID == "" {
		http.Error(w, `{"error": "房間 ID 是必填項"}`, http.StatusBadRequest)
		return
	}

	// 解析 multipart/form-data
	err := r.ParseMultipartForm(10 << 20) // 10MB 限制
	if err != nil {
		http.Error(w, `{"error": "無法解析上傳的文件"}`, http.StatusBadRequest)
		return
	}

	// 獲取上傳的語音文件
	file, header, err := r.FormFile("voice")
	if err != nil {
		http.Error(w, `{"error": "沒有找到語音文件"}`, http.StatusBadRequest)
		return
	}
	defer file.Close()

	// 獲取語音時長（由前端提供）
	durationStr := r.FormValue("duration")
	duration, err := strconv.Atoi(durationStr)
	if err != nil {
		duration = 0 // 如果解析失敗，設為0
	}

	// 驗證文件類型
	if !isValidAudioFile(header.Filename) {
		http.Error(w, `{"error": "不支持的音頻格式"}`, http.StatusBadRequest)
		return
	}

	// 驗證文件大小（例如限制為5MB）
	if header.Size > 5*1024*1024 {
		http.Error(w, `{"error": "文件大小超過限制（5MB）"}`, http.StatusBadRequest)
		return
	}

	cfg := config.LoadConfig()

	// 驗證用戶是否有權限訪問此聊天室
	roomCollection := store.Collection("chat_rooms")
	roomObjectID, err := primitive.ObjectIDFromHex(roomID)
	if err != nil {
		http.Error(w, `{"error": "無效的房間 ID"}`, http.StatusBadRequest)
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	roomFilter := bson.M{
		"_id": roomObjectID,
		"$or": []bson.M{
			{"participants": userID},
			{"created_by": userID},
		},
	}

	var room models.ChatRoom
	err = roomCollection.FindOne(ctx, roomFilter).Decode(&room)
	if err != nil {
		http.Error(w, `{"error": "聊天室不存在或無權限訪問"}`, http.StatusForbidden)
		return
	}

	// 上傳文件到存儲服務
	filePath, err := storageService.UploadFile(file, header, "audio")
	if err != nil {
		log.Printf("Error uploading voice file: %v", err)
		http.Error(w, `{"error": "文件上傳失敗"}`, http.StatusInternalServerError)
		return
	}

	// 獲取文件大小
	fileSize, err := storageService.GetFileSize(filePath)
	if err != nil {
		log.Printf("Warning: Could not get file size for %s: %v", filePath, err)
		fileSize = header.Size // 使用header中的大小作為備選
		log.Printf("Using header size as fallback: %d bytes", fileSize)
	} else {
		log.Printf("Successfully got file size: %d bytes", fileSize)
	}

	// 驗證文件大小是否合理
	if fileSize <= 0 {
		log.Printf("Warning: File size is 0 or negative: %d, using header size: %d", fileSize, header.Size)
		fileSize = header.Size
	}

	// 獲取用戶信息
	userCollection := store.Collection("users")
	userObjectID, err := primitive.ObjectIDFromHex(userID)
	if err != nil {
		http.Error(w, `{"error": "無效的用戶 ID"}`, http.StatusBadRequest)
		return
	}

	var user models.User
	err = userCollection.FindOne(ctx, bson.M{"_id": userObjectID}).Decode(&user)
	if err != nil {
		http.Error(w, `{"error": "無法獲取用戶信息"}`, http.StatusInternalServerError)
		return
	}

	// 🔥 關鍵修正：構建語音消息的內容，包含文件信息
	publicURL := storageService.GetPublicURL(filePath)
	voiceContent := map[string]interface{}{
		"file_url":  publicURL,
		"duration":  duration,
		"file_size": fileSize,
		"type":      "voice",
	}

	// 將語音消息內容轉為JSON字符串
	contentBytes, err := json.Marshal(voiceContent)
	if err != nil {
		http.Error(w, `{"error": "處理語音消息內容失敗"}`, http.StatusInternalServerError)
		return
	}

	// 加密內容
	encryptionKey := []byte(cfg.EncryptionSecret)
	encryptedContent, err := utils.Encrypt(string(contentBytes), encryptionKey)
	if err != nil {
		log.Printf("Error encrypting voice message content: %v", err)
		http.Error(w, `{"error": "處理語音消息失敗"}`, http.StatusInternalServerError)
		return
	}

	// 🔥 關鍵修正：創建統一的消息對象，存儲到 messages 集合
	voiceMessage := models.Message{
		ID:         primitive.NewObjectID(),
		SenderID:   userID,
		SenderName: user.Username,
		Room:       roomID,
		Content:    encryptedContent, // 存儲加密後的語音信息JSON
		Timestamp:  time.Now(),
		Type:       "voice", // 設置消息類型為 voice
	}

	// 🔥 關鍵修正：保存到 messages 集合而不是獨立的 voice_messages 集合
	messageCollection := store.Collection("messages")
	result, err := messageCollection.InsertOne(ctx, voiceMessage)
	if err != nil {
		log.Printf("Failed to save voice message: %v", err)
		http.Error(w, `{"error": "保存語音消息失敗"}`, http.StatusInternalServerError)
		return
	}

	// 更新聊天室信息
	roomUpdate := bson.M{
		"$set": bson.M{
			"last_message":      "[語音消息]",
			"last_message_time": voiceMessage.Timestamp,
			"updated_at":        time.Now(),
		},
		"$inc": bson.M{
			"unread_count": 1,
		},
	}

	_, err = roomCollection.UpdateOne(ctx, bson.M{"_id": roomObjectID}, roomUpdate)
	if err != nil {
		log.Printf("Failed to update room last message: %v", err)
	}

	// 🔥 構建響應 - 返回統一的消息格式
	response := map[string]interface{}{
		"message": "語音消息上傳成功",
		"voice_message": map[string]interface{}{
			"id":          voiceMessage.ID.Hex(),
			"sender_id":   userID,
			"sender_name": user.Username,
			"room":        roomID,
			"file_url":    publicURL,
			"duration":    duration,
			"file_size":   fileSize,
			"timestamp":   voiceMessage.Timestamp.Format(time.RFC3339),
			"type":        "voice",
		},
	}

	log.Printf("Voice message uploaded successfully - ID: %v, User: %s, Room: %s, Duration: %ds",
		result.InsertedID, user.Username, roomID, duration)

	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(response)
}

// GetVoiceMessageURL 獲取語音消息的播放URL - 🔥 從 messages 集合中查找
func GetVoiceMessageURL(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	// 從 JWT 中獲取用戶 ID
	userID, ok := r.Context().Value(middleware.UserIDKey).(string)
	if !ok {
		http.Error(w, `{"error": "無法獲取用戶 ID"}`, http.StatusUnauthorized)
		return
	}

	// 從 URL 參數中獲取語音消息 ID
	params := mux.Vars(r)
	messageID := params["messageId"]
	if messageID == "" {
		http.Error(w, `{"error": "消息 ID 是必填項"}`, http.StatusBadRequest)
		return
	}

	log.Printf("🎵 Getting voice message URL - MessageID: %s, UserID: %s", messageID, userID)

	messageObjectID, err := primitive.ObjectIDFromHex(messageID)
	if err != nil {
		log.Printf("❌ Invalid message ID: %s, Error: %v", messageID, err)
		http.Error(w, `{"error": "無效的消息 ID"}`, http.StatusBadRequest)
		return
	}

	cfg := config.LoadConfig()
	// 🔥 關鍵修正：從 messages 集合查找語音消息
	store, ok := getStore(r)
	if !ok {
		http.Error(w, `{"error": "資料庫尚未初始化"}`, http.StatusInternalServerError)
		return
	}
	messageCollection := store.Collection("messages")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// 查找語音消息
	var message models.Message
	err = messageCollection.FindOne(ctx, bson.M{
		"_id":  messageObjectID,
		"type": "voice", // 確保是語音消息
	}).Decode(&message)
	if err != nil {
		log.Printf("❌ Voice message not found: %s, Error: %v", messageID, err)
		http.Error(w, `{"error": "語音消息不存在"}`, http.StatusNotFound)
		return
	}

	log.Printf("✅ Found voice message: ID=%s, Room=%s, Type=%s", messageID, message.Room, message.Type)

	// 驗證用戶是否有權限訪問此消息（通過聊天室權限）
	roomCollection := store.Collection("chat_rooms")
	roomObjectID, err := primitive.ObjectIDFromHex(message.Room)
	if err != nil {
		log.Printf("❌ Invalid room ID: %s, Error: %v", message.Room, err)
		http.Error(w, `{"error": "無效的房間 ID"}`, http.StatusBadRequest)
		return
	}

	roomFilter := bson.M{
		"_id": roomObjectID,
		"$or": []bson.M{
			{"participants": userID},
			{"created_by": userID},
		},
	}

	var room models.ChatRoom
	err = roomCollection.FindOne(ctx, roomFilter).Decode(&room)
	if err != nil {
		log.Printf("❌ Permission denied or room not found: RoomID=%s, UserID=%s, Error: %v", message.Room, userID, err)
		http.Error(w, `{"error": "無權限訪問此語音消息"}`, http.StatusForbidden)
		return
	}

	log.Printf("✅ Room access verified: RoomID=%s, RoomName=%s", message.Room, room.Name)

	// 🔥 關鍵修正：解密消息內容並解析語音信息
	encryptionKey := []byte(cfg.EncryptionSecret)
	decryptedContent, err := utils.Decrypt(message.Content, encryptionKey)
	if err != nil {
		log.Printf("❌ Error decrypting message content for message %s: %v", messageID, err)
		http.Error(w, `{"error": "無法解密語音消息"}`, http.StatusInternalServerError)
		return
	}

	// 解析語音信息JSON
	var voiceInfo map[string]interface{}
	err = json.Unmarshal([]byte(decryptedContent), &voiceInfo)
	if err != nil {
		log.Printf("❌ Error parsing voice message content for message %s: %v", messageID, err)
		http.Error(w, `{"error": "語音消息格式錯誤"}`, http.StatusInternalServerError)
		return
	}

	fileURL, ok := voiceInfo["file_url"].(string)
	if !ok {
		log.Printf("❌ Missing file_url in voice message %s", messageID)
		http.Error(w, `{"error": "語音文件URL缺失"}`, http.StatusInternalServerError)
		return
	}

	log.Printf("🔐 Voice message content parsed successfully: URL=%s", fileURL)

	// 返回語音消息信息
	response := map[string]interface{}{
		"url":         fileURL,
		"duration":    voiceInfo["duration"],
		"file_size":   voiceInfo["file_size"],
		"message_id":  messageID,
		"room_id":     message.Room,
		"sender_name": message.SenderName,
	}

	log.Printf("🎉 Voice message URL response: %+v", response)

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}

// 🔥 新增：调试端点，用于检查語音消息狀態
func DebugVoiceMessage(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	params := mux.Vars(r)
	messageID := params["messageId"]

	cfg := config.LoadConfig()
	store, ok := getStore(r)
	if !ok {
		http.Error(w, `{"error": "資料庫尚未初始化"}`, http.StatusInternalServerError)
		return
	}
	messageCollection := store.Collection("messages")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	messageObjectID, _ := primitive.ObjectIDFromHex(messageID)
	var message models.Message
	err := messageCollection.FindOne(ctx, bson.M{
		"_id":  messageObjectID,
		"type": "voice",
	}).Decode(&message)

	debugInfo := map[string]interface{}{
		"message_exists": err == nil,
		"error":          nil,
	}

	if err != nil {
		debugInfo["error"] = err.Error()
	} else {
		encryptionKey := []byte(cfg.EncryptionSecret)
		decryptedContent, decryptErr := utils.Decrypt(message.Content, encryptionKey)

		debugInfo["encrypted_content"] = message.Content
		debugInfo["decrypted_content"] = decryptedContent
		debugInfo["decrypt_error"] = nil
		if decryptErr != nil {
			debugInfo["decrypt_error"] = decryptErr.Error()
		}

		if decryptErr == nil {
			var voiceInfo map[string]interface{}
			jsonErr := json.Unmarshal([]byte(decryptedContent), &voiceInfo)
			debugInfo["voice_info"] = voiceInfo
			debugInfo["json_parse_error"] = nil
			if jsonErr != nil {
				debugInfo["json_parse_error"] = jsonErr.Error()
			}
		}

		debugInfo["room_id"] = message.Room
		debugInfo["sender_name"] = message.SenderName
		debugInfo["timestamp"] = message.Timestamp
		debugInfo["type"] = message.Type
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(debugInfo)
}

// isValidAudioFile 檢查是否為有效的音頻文件
func isValidAudioFile(filename string) bool {
	validExtensions := []string{".mp3", ".wav", ".ogg", ".opus", ".aac", ".m4a", ".webm"}
	filename = strings.ToLower(filename)

	for _, ext := range validExtensions {
		if strings.HasSuffix(filename, ext) {
			return true
		}
	}
	return false
}
