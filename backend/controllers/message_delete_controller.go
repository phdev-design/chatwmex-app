package controllers

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"time"

	"chatwme/backend/config"
	"chatwme/backend/database"
	"chatwme/backend/middleware"
	"chatwme/backend/models"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
)

// DeleteMessageRequest 刪除消息請求結構
type DeleteMessageRequest struct {
	MessageID string `json:"message_id"`
}

// DeleteMessageResponse 刪除消息響應結構
type DeleteMessageResponse struct {
	Message string `json:"message"`
	Success bool   `json:"success"`
}

// DeleteMessage 刪除用戶自己的消息（偽刪除）
func DeleteMessage(w http.ResponseWriter, r *http.Request) {
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

	// 解析請求體
	var req DeleteMessageRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		log.Printf("解析刪除消息請求失敗: %v", err)
		http.Error(w, `{"error": "無效的請求格式"}`, http.StatusBadRequest)
		return
	}

	if req.MessageID == "" {
		http.Error(w, `{"error": "消息 ID 為必填項"}`, http.StatusBadRequest)
		return
	}

	log.Printf("收到刪除消息請求 - UserID: %s, MessageID: %s", userID, req.MessageID)

	cfg := config.LoadConfig()
	messageCollection := database.GetCollection("messages", cfg.MongoDbName)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// 將字符串 ID 轉換為 ObjectID
	messageObjectID, err := primitive.ObjectIDFromHex(req.MessageID)
	if err != nil {
		http.Error(w, `{"error": "無效的消息 ID"}`, http.StatusBadRequest)
		return
	}

	// 查找消息
	var message models.Message
	err = messageCollection.FindOne(ctx, bson.M{"_id": messageObjectID}).Decode(&message)
	if err != nil {
		if err == mongo.ErrNoDocuments {
			http.Error(w, `{"error": "消息不存在"}`, http.StatusNotFound)
		} else {
			log.Printf("查找消息時發生錯誤: %v", err)
			http.Error(w, `{"error": "查找消息時發生錯誤"}`, http.StatusInternalServerError)
		}
		return
	}

	// 檢查消息是否已經被刪除
	if message.IsDeleted {
		http.Error(w, `{"error": "消息已經被刪除"}`, http.StatusBadRequest)
		return
	}

	// 檢查用戶是否有權限刪除此消息（只能刪除自己的消息）
	if message.SenderID != userID {
		http.Error(w, `{"error": "只能刪除自己的消息"}`, http.StatusForbidden)
		return
	}

	// 執行偽刪除
	now := time.Now()
	updateResult, err := messageCollection.UpdateOne(
		ctx,
		bson.M{"_id": messageObjectID},
		bson.M{
			"$set": bson.M{
				"is_deleted": true,
				"deleted_at": now,
				"deleted_by": userID,
			},
		},
	)
	if err != nil {
		log.Printf("刪除消息失敗: %v", err)
		http.Error(w, `{"error": "刪除消息失敗"}`, http.StatusInternalServerError)
		return
	}

	if updateResult.MatchedCount == 0 {
		http.Error(w, `{"error": "消息不存在"}`, http.StatusNotFound)
		return
	}

	log.Printf("消息刪除成功 - UserID: %s, MessageID: %s", userID, req.MessageID)

	// 返回成功響應
	response := DeleteMessageResponse{
		Message: "消息刪除成功",
		Success: true,
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}

// RestoreMessage 恢復已刪除的消息
func RestoreMessage(w http.ResponseWriter, r *http.Request) {
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

	// 解析請求體
	var req DeleteMessageRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		log.Printf("解析恢復消息請求失敗: %v", err)
		http.Error(w, `{"error": "無效的請求格式"}`, http.StatusBadRequest)
		return
	}

	if req.MessageID == "" {
		http.Error(w, `{"error": "消息 ID 為必填項"}`, http.StatusBadRequest)
		return
	}

	log.Printf("收到恢復消息請求 - UserID: %s, MessageID: %s", userID, req.MessageID)

	cfg := config.LoadConfig()
	messageCollection := database.GetCollection("messages", cfg.MongoDbName)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// 將字符串 ID 轉換為 ObjectID
	messageObjectID, err := primitive.ObjectIDFromHex(req.MessageID)
	if err != nil {
		http.Error(w, `{"error": "無效的消息 ID"}`, http.StatusBadRequest)
		return
	}

	// 查找消息
	var message models.Message
	err = messageCollection.FindOne(ctx, bson.M{"_id": messageObjectID}).Decode(&message)
	if err != nil {
		if err == mongo.ErrNoDocuments {
			http.Error(w, `{"error": "消息不存在"}`, http.StatusNotFound)
		} else {
			log.Printf("查找消息時發生錯誤: %v", err)
			http.Error(w, `{"error": "查找消息時發生錯誤"}`, http.StatusInternalServerError)
		}
		return
	}

	// 檢查消息是否已經被刪除
	if !message.IsDeleted {
		http.Error(w, `{"error": "消息未被刪除"}`, http.StatusBadRequest)
		return
	}

	// 檢查用戶是否有權限恢復此消息（只能恢復自己刪除的消息）
	if message.DeletedBy == nil || *message.DeletedBy != userID {
		http.Error(w, `{"error": "只能恢復自己刪除的消息"}`, http.StatusForbidden)
		return
	}

	// 執行恢復
	updateResult, err := messageCollection.UpdateOne(
		ctx,
		bson.M{"_id": messageObjectID},
		bson.M{
			"$unset": bson.M{
				"is_deleted": "",
				"deleted_at": "",
				"deleted_by": "",
			},
		},
	)
	if err != nil {
		log.Printf("恢復消息失敗: %v", err)
		http.Error(w, `{"error": "恢復消息失敗"}`, http.StatusInternalServerError)
		return
	}

	if updateResult.MatchedCount == 0 {
		http.Error(w, `{"error": "消息不存在"}`, http.StatusNotFound)
		return
	}

	log.Printf("消息恢復成功 - UserID: %s, MessageID: %s", userID, req.MessageID)

	// 返回成功響應
	response := DeleteMessageResponse{
		Message: "消息恢復成功",
		Success: true,
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}

// GetDeletedMessages 獲取用戶已刪除的消息列表
func GetDeletedMessages(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	// 從 JWT 中獲取用戶 ID
	userID, ok := r.Context().Value(middleware.UserIDKey).(string)
	if !ok {
		http.Error(w, `{"error": "無法獲取用戶 ID"}`, http.StatusUnauthorized)
		return
	}

	log.Printf("收到獲取已刪除消息請求 - UserID: %s", userID)

	cfg := config.LoadConfig()
	messageCollection := database.GetCollection("messages", cfg.MongoDbName)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// 查詢用戶已刪除的消息
	filter := bson.M{
		"sender_id":  userID,
		"is_deleted": true,
	}

	cursor, err := messageCollection.Find(ctx, filter)
	if err != nil {
		log.Printf("查詢已刪除消息失敗: %v", err)
		http.Error(w, `{"error": "查詢已刪除消息失敗"}`, http.StatusInternalServerError)
		return
	}
	defer cursor.Close(ctx)

	var messages []models.Message
	if err = cursor.All(ctx, &messages); err != nil {
		log.Printf("解析已刪除消息失敗: %v", err)
		http.Error(w, `{"error": "解析已刪除消息失敗"}`, http.StatusInternalServerError)
		return
	}

	if messages == nil {
		messages = []models.Message{}
	}

	log.Printf("找到 %d 條已刪除消息 - UserID: %s", len(messages), userID)

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"messages": messages,
		"count":    len(messages),
	})
}
