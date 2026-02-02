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

	"github.com/gorilla/mux"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo/options"
)

// CreateRoomRequest 創建聊天室的請求結構
type CreateRoomRequest struct {
	Name         string   `json:"name"`
	IsGroup      bool     `json:"is_group"`
	Participants []string `json:"participants"`
}

// GetChatRooms 獲取用戶的聊天室列表
func GetChatRooms(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	// 從 JWT 中獲取用戶 ID
	userID, ok := r.Context().Value(middleware.UserIDKey).(string)
	if !ok {
		http.Error(w, `{"error": "無法獲取用戶 ID"}`, http.StatusUnauthorized)
		return
	}

	cfg := config.LoadConfig()
	roomCollection := database.GetCollection("chat_rooms", cfg.MongoDbName)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// 查找用戶參與的所有聊天室
	filter := bson.M{
		"$or": []bson.M{
			{"participants": userID},
			{"created_by": userID},
		},
	}

	// 按最後消息時間降序排序
	findOptions := options.Find()
	findOptions.SetSort(bson.D{{Key: "last_message_time", Value: -1}})

	cursor, err := roomCollection.Find(ctx, filter, findOptions)
	if err != nil {
		http.Error(w, `{"error": "查詢聊天室時發生錯誤"}`, http.StatusInternalServerError)
		log.Printf("Error finding chat rooms for user %s: %v", userID, err)
		return
	}
	defer cursor.Close(ctx)

	var rooms []models.ChatRoom
	if err = cursor.All(ctx, &rooms); err != nil {
		http.Error(w, `{"error": "讀取聊天室資料時發生錯誤"}`, http.StatusInternalServerError)
		log.Printf("Error decoding chat rooms: %v", err)
		return
	}

	// 如果沒有找到聊天室，返回空陣列
	if rooms == nil {
		rooms = []models.ChatRoom{}
	}

	// 返回聊天室列表
	response := map[string]interface{}{
		"rooms": rooms,
	}

	w.WriteHeader(http.StatusOK)
	if err := json.NewEncoder(w).Encode(response); err != nil {
		log.Printf("Error encoding rooms to JSON: %v", err)
	}
}

// CreateChatRoom 創建新的聊天室
func CreateChatRoom(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	// 從 JWT 中獲取用戶 ID
	userID, ok := r.Context().Value(middleware.UserIDKey).(string)
	if !ok {
		http.Error(w, `{"error": "無法獲取用戶 ID"}`, http.StatusUnauthorized)
		return
	}

	var req CreateRoomRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		log.Printf("Error decoding create room request: %v", err)
		http.Error(w, `{"error": "無效的請求格式"}`, http.StatusBadRequest)
		return
	}

	// 驗證輸入
	if req.Name == "" {
		http.Error(w, `{"error": "聊天室名稱為必填項"}`, http.StatusBadRequest)
		return
	}

	cfg := config.LoadConfig()
	roomCollection := database.GetCollection("chat_rooms", cfg.MongoDbName)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// 確保創建者包含在參與者列表中
	participants := req.Participants
	userIncluded := false
	for _, participant := range participants {
		if participant == userID {
			userIncluded = true
			break
		}
	}
	if !userIncluded {
		participants = append(participants, userID)
	}

	// 創建新聊天室
	newRoom := models.ChatRoom{
		ID:              primitive.NewObjectID(),
		Name:            req.Name,
		IsGroup:         req.IsGroup,
		Participants:    participants,
		CreatedBy:       userID,
		LastMessage:     "",
		LastMessageTime: time.Now(),
		UnreadCount:     0,
		CreatedAt:       time.Now(),
		UpdatedAt:       time.Now(),
	}

	result, err := roomCollection.InsertOne(ctx, newRoom)
	if err != nil {
		log.Printf("Failed to create chat room: %v", err)
		http.Error(w, `{"error": "創建聊天室失敗"}`, http.StatusInternalServerError)
		return
	}

	log.Printf("Chat room created successfully - ID: %v, Name: %s, CreatedBy: %s", 
		result.InsertedID, req.Name, userID)

	// 返回創建的聊天室
	response := map[string]interface{}{
		"message": "聊天室創建成功",
		"room":    newRoom,
	}

	w.WriteHeader(http.StatusCreated)
	if err := json.NewEncoder(w).Encode(response); err != nil {
		log.Printf("Error encoding response: %v", err)
	}
}

// GetRoomDetails 獲取聊天室詳情
func GetRoomDetails(w http.ResponseWriter, r *http.Request) {
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
	if roomID == "" {
		http.Error(w, `{"error": "房間 ID 為必填項"}`, http.StatusBadRequest)
		return
	}

	// 轉換為 ObjectID
	objectID, err := primitive.ObjectIDFromHex(roomID)
	if err != nil {
		http.Error(w, `{"error": "無效的房間 ID"}`, http.StatusBadRequest)
		return
	}

	cfg := config.LoadConfig()
	roomCollection := database.GetCollection("chat_rooms", cfg.MongoDbName)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// 查找聊天室並確保用戶有權限訪問
	filter := bson.M{
		"_id": objectID,
		"$or": []bson.M{
			{"participants": userID},
			{"created_by": userID},
		},
	}

	var room models.ChatRoom
	err = roomCollection.FindOne(ctx, filter).Decode(&room)
	if err != nil {
		http.Error(w, `{"error": "聊天室不存在或無權限訪問"}`, http.StatusNotFound)
		return
	}

	// 返回聊天室詳情
	response := map[string]interface{}{
		"room": room,
	}

	w.WriteHeader(http.StatusOK)
	if err := json.NewEncoder(w).Encode(response); err != nil {
		log.Printf("Error encoding response: %v", err)
	}
}

// InviteToRoom 邀請用戶加入聊天室
func InviteToRoom(w http.ResponseWriter, r *http.Request) {
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

	var req struct {
		UserID string `json:"user_id"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error": "無效的請求格式"}`, http.StatusBadRequest)
		return
	}

	if req.UserID == "" {
		http.Error(w, `{"error": "用戶 ID 為必填項"}`, http.StatusBadRequest)
		return
	}

	// 轉換為 ObjectID
	objectID, err := primitive.ObjectIDFromHex(roomID)
	if err != nil {
		http.Error(w, `{"error": "無效的房間 ID"}`, http.StatusBadRequest)
		return
	}

	cfg := config.LoadConfig()
	roomCollection := database.GetCollection("chat_rooms", cfg.MongoDbName)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// 添加用戶到參與者列表
	filter := bson.M{
		"_id": objectID,
		"$or": []bson.M{
			{"participants": userID},
			{"created_by": userID},
		},
	}

	update := bson.M{
		"$addToSet": bson.M{"participants": req.UserID},
		"$set":      bson.M{"updated_at": time.Now()},
	}

	result, err := roomCollection.UpdateOne(ctx, filter, update)
	if err != nil {
		log.Printf("Error inviting user to room: %v", err)
		http.Error(w, `{"error": "邀請用戶失敗"}`, http.StatusInternalServerError)
		return
	}

	if result.MatchedCount == 0 {
		http.Error(w, `{"error": "聊天室不存在或無權限操作"}`, http.StatusNotFound)
		return
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"message": "用戶邀請成功"})
}

// LeaveRoom 離開聊天室
func LeaveRoom(w http.ResponseWriter, r *http.Request) {
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

	// 轉換為 ObjectID
	objectID, err := primitive.ObjectIDFromHex(roomID)
	if err != nil {
		http.Error(w, `{"error": "無效的房間 ID"}`, http.StatusBadRequest)
		return
	}

	cfg := config.LoadConfig()
	roomCollection := database.GetCollection("chat_rooms", cfg.MongoDbName)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// 從參與者列表中移除用戶
	filter := bson.M{"_id": objectID}
	update := bson.M{
		"$pull": bson.M{"participants": userID},
		"$set":  bson.M{"updated_at": time.Now()},
	}

	result, err := roomCollection.UpdateOne(ctx, filter, update)
	if err != nil {
		log.Printf("Error leaving room: %v", err)
		http.Error(w, `{"error": "離開聊天室失敗"}`, http.StatusInternalServerError)
		return
	}

	if result.MatchedCount == 0 {
		http.Error(w, `{"error": "聊天室不存在"}`, http.StatusNotFound)
		return
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"message": "已離開聊天室"})
}

// MarkAsRead 標記聊天室為已讀
func MarkAsRead(w http.ResponseWriter, r *http.Request) {
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

	// 轉換為 ObjectID
	objectID, err := primitive.ObjectIDFromHex(roomID)
	if err != nil {
		http.Error(w, `{"error": "無效的房間 ID"}`, http.StatusBadRequest)
		return
	}

	cfg := config.LoadConfig()
	roomCollection := database.GetCollection("chat_rooms", cfg.MongoDbName)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// 將未讀計數重置為 0
	filter := bson.M{
		"_id": objectID,
		"$or": []bson.M{
			{"participants": userID},
			{"created_by": userID},
		},
	}

	update := bson.M{
		"$set": bson.M{
			"unread_count": 0,
			"updated_at":   time.Now(),
		},
	}

	result, err := roomCollection.UpdateOne(ctx, filter, update)
	if err != nil {
		log.Printf("Error marking room as read: %v", err)
		http.Error(w, `{"error": "標記已讀失敗"}`, http.StatusInternalServerError)
		return
	}

	if result.MatchedCount == 0 {
		http.Error(w, `{"error": "聊天室不存在或無權限訪問"}`, http.StatusNotFound)
		return
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"message": "已標記為已讀"})
}