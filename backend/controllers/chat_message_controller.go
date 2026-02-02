package controllers

import (
	"chatwme/backend/config"
	"chatwme/backend/database"
	"chatwme/backend/middleware"
	"chatwme/backend/models"
	"chatwme/backend/utils"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gorilla/mux"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo/options"
)

// SendMessageRequest 發送消息的請求結構
type SendMessageRequest struct {
	Content string `json:"content"`
	Type    string `json:"type"`
	// 🔥 新增語音消息相關字段
	FileURL  string `json:"file_url,omitempty"`
	Duration int    `json:"duration,omitempty"`
	FileSize int64  `json:"file_size,omitempty"`
}

// 🔥 修正后的 GetMessagesByRoom 函数 - 正确处理语音消息解密
func GetMessagesByRoom(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	// 从 JWT 中获取用户 ID
	userID, ok := r.Context().Value(middleware.UserIDKey).(string)
	if !ok {
		http.Error(w, `{"error": "无法获取用户 ID"}`, http.StatusUnauthorized)
		return
	}

	// 从 URL 参数中获取房间 ID
	params := mux.Vars(r)
	roomID, ok := params["id"]
	if !ok || roomID == "" {
		http.Error(w, `{"error": "房间 ID 是必填项"}`, http.StatusBadRequest)
		return
	}

	// 获取分页参数
	pageStr := r.URL.Query().Get("page")
	limitStr := r.URL.Query().Get("limit")
	includeVoice := r.URL.Query().Get("include_voice") == "true"

	page := 1
	limit := 50

	if pageStr != "" {
		if p, err := strconv.Atoi(pageStr); err == nil && p > 0 {
			page = p
		}
	}

	if limitStr != "" {
		if l, err := strconv.Atoi(limitStr); err == nil && l > 0 && l <= 100 {
			limit = l
		}
	}

	cfg := config.LoadConfig()

	// 验证用户权限
	roomCollection := database.GetCollection("chat_rooms", cfg.MongoDbName)
	roomObjectID, err := primitive.ObjectIDFromHex(roomID)
	if err != nil {
		http.Error(w, `{"error": "无效的房间 ID"}`, http.StatusBadRequest)
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
		http.Error(w, `{"error": "聊天室不存在或无权限访问"}`, http.StatusForbidden)
		return
	}

	// 获取消息
	messageCollection := database.GetCollection("messages", cfg.MongoDbName)
	skip := (page - 1) * limit

	filter := bson.M{
		"room":       roomID,
		"is_deleted": bson.M{"$ne": true}, // 排除已刪除的消息
	}
	if includeVoice {
		log.Printf("Including voice messages in query for room %s", roomID)
	}

	findOptions := options.Find()
	findOptions.SetSort(bson.D{{Key: "timestamp", Value: -1}})
	findOptions.SetLimit(int64(limit))
	findOptions.SetSkip(int64(skip))

	cursor, err := messageCollection.Find(ctx, filter, findOptions)
	if err != nil {
		http.Error(w, `{"error": "查询讯息时发生错误"}`, http.StatusInternalServerError)
		log.Printf("Error finding messages for room %s: %v", roomID, err)
		return
	}
	defer cursor.Close(ctx)

	var messages []models.Message
	if err = cursor.All(ctx, &messages); err != nil {
		http.Error(w, `{"error": "读取讯息资料时发生错误"}`, http.StatusInternalServerError)
		log.Printf("Error decoding messages: %v", err)
		return
	}

	encryptionKey := []byte(cfg.EncryptionSecret)
	userCollection := database.GetCollection("users", cfg.MongoDbName)

	// 🔥 关键修正：处理所有消息类型并正确解密
	decryptedMessages := make([]map[string]interface{}, 0, len(messages))
	for _, msg := range messages {
		// 解密消息内容
		decryptedContent, err := utils.Decrypt(msg.Content, encryptionKey)
		if err != nil {
			log.Printf("Could not decrypt message ID %s: %v", msg.ID.Hex(), err)
			decryptedContent = "[讯息无法解密]"
		}

		// 确保有发送者姓名
		senderName := msg.SenderName
		if senderName == "" {
			senderObjectID, err := primitive.ObjectIDFromHex(msg.SenderID)
			if err == nil {
				var user models.User
				err = userCollection.FindOne(ctx, bson.M{"_id": senderObjectID}).Decode(&user)
				if err == nil {
					senderName = user.Username
				} else {
					senderName = "未知用户"
				}
			} else {
				senderName = "未知用户"
			}
		}

		// 🔥 构建基本消息对象
		messageObj := map[string]interface{}{
			"id":          msg.ID.Hex(),
			"sender_id":   msg.SenderID,
			"sender_name": senderName,
			"room":        msg.Room,
			"timestamp":   msg.Timestamp.Format(time.RFC3339),
			"type":        msg.Type,
		}

		if msg.Type == "voice" {
			// 语音消息：解析JSON内容并添加相关字段
			var voiceInfo map[string]interface{}
			if err := json.Unmarshal([]byte(decryptedContent), &voiceInfo); err == nil {
				messageObj["content"] = "[语音消息]" // 显示文本
				messageObj["file_url"] = voiceInfo["file_url"]
				messageObj["duration"] = voiceInfo["duration"]
				messageObj["file_size"] = voiceInfo["file_size"]
			} else {
				log.Printf("Error parsing voice message content for message %s: %v", msg.ID.Hex(), err)
				// 🔥 新增：尝试处理旧格式的语音消息
				if strings.Contains(decryptedContent, "audio/") || strings.Contains(decryptedContent, ".m4a") {
					// 可能是旧格式，直接作为文件路径使用
					baseURL := "https://api-chatwmex.phdev.uk/uploads"
					fileURL := decryptedContent
					if !strings.HasPrefix(fileURL, "http") {
						normalizedPath := strings.ReplaceAll(decryptedContent, "\\", "/")
						fileURL = fmt.Sprintf("%s/%s", strings.TrimRight(baseURL, "/"), strings.TrimLeft(normalizedPath, "/"))
					}

					messageObj["content"] = "[语音消息]"
					messageObj["file_url"] = fileURL
					messageObj["duration"] = 0  // 默认值
					messageObj["file_size"] = 0 // 默认值

					log.Printf("✅ Processed legacy voice message %s: %s", msg.ID.Hex(), fileURL)
				} else {
					// 完全无法解析的消息
					messageObj["content"] = "[语音消息解析失败]"
					messageObj["file_url"] = nil
					messageObj["duration"] = 0
					messageObj["file_size"] = 0
				}
			}
		} else {
			// 普通文本消息
			messageObj["content"] = decryptedContent
		}

		decryptedMessages = append(decryptedMessages, messageObj)
	}

	// 反转数组，使最旧的消息在前
	for i, j := 0, len(decryptedMessages)-1; i < j; i, j = i+1, j-1 {
		decryptedMessages[i], decryptedMessages[j] = decryptedMessages[j], decryptedMessages[i]
	}

	if decryptedMessages == nil {
		decryptedMessages = []map[string]interface{}{}
	}

	response := map[string]interface{}{
		"messages": decryptedMessages,
		"page":     page,
		"limit":    limit,
		"total":    len(decryptedMessages),
	}

	log.Printf("✅ Returning %d messages for room %s (voice messages included: %v)",
		len(decryptedMessages), roomID, includeVoice)

	w.WriteHeader(http.StatusOK)
	if err := json.NewEncoder(w).Encode(response); err != nil {
		log.Printf("Error encoding messages to JSON: %v", err)
	}
}

// SendMessage 發送消息到指定聊天室 - 🔥 支援語音消息
func SendMessage(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	// 從 JWT 中獲取用戶 ID
	userID, ok := r.Context().Value(middleware.UserIDKey).(string)
	if !ok {
		http.Error(w, `{"error": "無法獲取用戶 ID"}`, http.StatusUnauthorized)
		return
	}

	// 從 URL 參數中獲取房間 ID
	params := mux.Vars(r)
	roomID := params["id"]

	var req SendMessageRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error": "無效的請求格式"}`, http.StatusBadRequest)
		return
	}

	if req.Content == "" {
		http.Error(w, `{"error": "消息內容不能為空"}`, http.StatusBadRequest)
		return
	}

	if req.Type == "" {
		req.Type = "text"
	}

	cfg := config.LoadConfig()

	// 驗證用戶是否有權限訪問此聊天室
	roomCollection := database.GetCollection("chat_rooms", cfg.MongoDbName)
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

	// 🔥 修正：根據消息類型處理不同的內容加密
	var encryptedContent string
	encryptionKey := []byte(cfg.EncryptionSecret)

	if req.Type == "voice" {
		// 語音消息：構建語音信息JSON並加密
		voiceInfo := map[string]interface{}{
			"file_url":  req.FileURL,
			"duration":  req.Duration,
			"file_size": req.FileSize,
			"type":      "voice",
		}

		contentBytes, err := json.Marshal(voiceInfo)
		if err != nil {
			http.Error(w, `{"error": "語音消息格式處理失敗"}`, http.StatusInternalServerError)
			return
		}

		encryptedContent, err = utils.Encrypt(string(contentBytes), encryptionKey)
		if err != nil {
			log.Printf("Error encrypting voice message: %v", err)
			http.Error(w, `{"error": "語音消息加密失敗"}`, http.StatusInternalServerError)
			return
		}
	} else {
		// 普通文本消息：直接加密內容
		encryptedContent, err = utils.Encrypt(req.Content, encryptionKey)
		if err != nil {
			log.Printf("Error encrypting message: %v", err)
			http.Error(w, `{"error": "消息加密失敗"}`, http.StatusInternalServerError)
			return
		}
	}

	// 獲取用戶信息以填充發送者名稱
	userCollection := database.GetCollection("users", cfg.MongoDbName)
	userObjectID, err := primitive.ObjectIDFromHex(userID)
	if err != nil {
		http.Error(w, `{"error": "無效的用戶 ID"}`, http.StatusBadRequest)
		return
	}

	var user models.User
	err = userCollection.FindOne(ctx, bson.M{"_id": userObjectID}).Decode(&user)
	if err != nil {
		log.Printf("Warning: Could not get user info for %s: %v", userID, err)
		user.Username = "未知用户" // 設置默認值
	}

	// 創建新消息
	newMessage := models.Message{
		ID:         primitive.NewObjectID(),
		SenderID:   userID,
		SenderName: user.Username, // 🔥 確保包含發送者名稱
		Room:       roomID,
		Content:    encryptedContent, // 存儲加密後的內容
		Timestamp:  time.Now(),
		Type:       req.Type, // 🔥 確保包含消息類型
	}

	// 保存消息到資料庫
	messageCollection := database.GetCollection("messages", cfg.MongoDbName)
	result, err := messageCollection.InsertOne(ctx, newMessage)
	if err != nil {
		log.Printf("Failed to save message: %v", err)
		http.Error(w, `{"error": "保存消息失敗"}`, http.StatusInternalServerError)
		return
	}

	// 更新聊天室的最後消息
	lastMessageContent := req.Content
	if req.Type == "voice" {
		lastMessageContent = "[語音消息]" // 為語音消息顯示特殊文本
	}

	roomUpdate := bson.M{
		"$set": bson.M{
			"last_message":      lastMessageContent,
			"last_message_time": newMessage.Timestamp,
			"updated_at":        time.Now(),
		},
		"$inc": bson.M{
			"unread_count": 1, // 增加未讀計數
		},
	}

	_, err = roomCollection.UpdateOne(ctx, bson.M{"_id": roomObjectID}, roomUpdate)
	if err != nil {
		log.Printf("Failed to update room last message: %v", err)
	}

	// 🔥 修正：構建返回的消息對象，根據類型包含不同字段
	responseMessage := map[string]interface{}{
		"id":          newMessage.ID.Hex(),
		"sender_id":   userID,
		"sender_name": user.Username,
		"room":        roomID,
		"content":     req.Content, // 返回原始內容/顯示文本
		"timestamp":   newMessage.Timestamp.Format(time.RFC3339),
		"type":        req.Type,
	}

	// 如果是語音消息，添加語音相關字段
	if req.Type == "voice" {
		responseMessage["file_url"] = req.FileURL
		responseMessage["duration"] = req.Duration
		responseMessage["file_size"] = req.FileSize
		responseMessage["content"] = "[语音消息]" // 顯示文本
	}

	response := map[string]interface{}{
		"message": responseMessage,
		"id":      result.InsertedID,
	}

	log.Printf("Message sent successfully - Room: %s, User: %s, Type: %s", roomID, user.Username, req.Type)

	w.WriteHeader(http.StatusCreated)
	if err := json.NewEncoder(w).Encode(response); err != nil {
		log.Printf("Error encoding response: %v", err)
	}
}
