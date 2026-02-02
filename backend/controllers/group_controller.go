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

// CreateGroupRequest 創建群組請求結構
type CreateGroupRequest struct {
	Name        string `json:"name"`
	Description string `json:"description,omitempty"`
	GroupType   string `json:"group_type"` // public, private, invite_only
	MaxMembers  int    `json:"max_members,omitempty"`
}

// JoinGroupRequest 加入群組請求結構
type JoinGroupRequest struct {
	GroupID string `json:"group_id"`
}

// InviteToGroupRequest 邀請加入群組請求結構
type InviteToGroupRequest struct {
	GroupID      string `json:"group_id"`
	InviteeEmail string `json:"invitee_email"`
	Message      string `json:"message,omitempty"`
}

// GroupResponse 群組響應結構
type GroupResponse struct {
	ID          string    `json:"id"`
	Name        string    `json:"name"`
	Description string    `json:"description"`
	GroupType   string    `json:"group_type"`
	MaxMembers  int       `json:"max_members"`
	MemberCount int       `json:"member_count"`
	Admins      []string  `json:"admins"`
	CreatedBy   string    `json:"created_by"`
	IsActive    bool      `json:"is_active"`
	AvatarURL   string    `json:"avatar_url"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

// CreateGroup 創建群組
func CreateGroup(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	// 從 JWT 中獲取用戶 ID
	userID, ok := r.Context().Value(middleware.UserIDKey).(string)
	if !ok {
		http.Error(w, `{"error": "無法獲取用戶 ID"}`, http.StatusUnauthorized)
		return
	}

	// 解析請求體
	var req CreateGroupRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		log.Printf("解析創建群組請求失敗: %v", err)
		http.Error(w, `{"error": "無效的請求格式"}`, http.StatusBadRequest)
		return
	}

	// 驗證必填字段
	if req.Name == "" {
		http.Error(w, `{"error": "群組名稱為必填項"}`, http.StatusBadRequest)
		return
	}

	if req.GroupType == "" {
		req.GroupType = "private" // 默認為私有群組
	}

	if req.MaxMembers == 0 {
		req.MaxMembers = 1000 // 默認最大 1000 人
	}

	if req.MaxMembers > 1000 {
		http.Error(w, `{"error": "群組最大成員數不能超過 1000 人"}`, http.StatusBadRequest)
		return
	}

	log.Printf("收到創建群組請求 - UserID: %s, GroupName: %s", userID, req.Name)

	cfg := config.LoadConfig()
	groupCollection := database.GetCollection("chat_rooms", cfg.MongoDbName)
	userCollection := database.GetCollection("users", cfg.MongoDbName)
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// 獲取用戶信息
	var user models.User
	userObjectID, err := primitive.ObjectIDFromHex(userID)
	if err != nil {
		http.Error(w, `{"error": "無效的用戶 ID"}`, http.StatusBadRequest)
		return
	}

	err = userCollection.FindOne(ctx, bson.M{"_id": userObjectID}).Decode(&user)
	if err != nil {
		http.Error(w, `{"error": "用戶不存在"}`, http.StatusNotFound)
		return
	}

	// 創建群組
	now := time.Now()
	group := models.ChatRoom{
		ID:           primitive.NewObjectID(),
		Name:         req.Name,
		Description:  req.Description,
		IsGroup:      true,
		GroupType:    req.GroupType,
		MaxMembers:   req.MaxMembers,
		Participants: []string{userID},
		Admins:       []string{userID},
		CreatedBy:    userID,
		IsActive:     true,
		CreatedAt:    now,
		UpdatedAt:    now,
	}

	_, err = groupCollection.InsertOne(ctx, group)
	if err != nil {
		log.Printf("創建群組失敗: %v", err)
		http.Error(w, `{"error": "創建群組失敗"}`, http.StatusInternalServerError)
		return
	}

	log.Printf("群組創建成功 - GroupID: %s, GroupName: %s", group.ID.Hex(), req.Name)

	// 返回群組信息
	response := GroupResponse{
		ID:          group.ID.Hex(),
		Name:        group.Name,
		Description: group.Description,
		GroupType:   group.GroupType,
		MaxMembers:  group.MaxMembers,
		MemberCount: 1,
		Admins:      group.Admins,
		CreatedBy:   group.CreatedBy,
		IsActive:    group.IsActive,
		AvatarURL:   group.AvatarURL,
		CreatedAt:   group.CreatedAt,
		UpdatedAt:   group.UpdatedAt,
	}

	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"message": "群組創建成功",
		"group":   response,
	})
}

// GetUserGroups 獲取用戶的群組列表
func GetUserGroups(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	// 從 JWT 中獲取用戶 ID
	userID, ok := r.Context().Value(middleware.UserIDKey).(string)
	if !ok {
		http.Error(w, `{"error": "無法獲取用戶 ID"}`, http.StatusUnauthorized)
		return
	}

	log.Printf("收到獲取用戶群組請求 - UserID: %s", userID)

	cfg := config.LoadConfig()
	groupCollection := database.GetCollection("chat_rooms", cfg.MongoDbName)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// 查詢用戶參與的群組
	filter := bson.M{
		"is_group":     true,
		"participants": userID,
		"is_active":    true,
	}

	cursor, err := groupCollection.Find(ctx, filter)
	if err != nil {
		log.Printf("查詢用戶群組失敗: %v", err)
		http.Error(w, `{"error": "查詢用戶群組失敗"}`, http.StatusInternalServerError)
		return
	}
	defer cursor.Close(ctx)

	var groups []models.ChatRoom
	if err = cursor.All(ctx, &groups); err != nil {
		log.Printf("解析用戶群組失敗: %v", err)
		http.Error(w, `{"error": "解析用戶群組失敗"}`, http.StatusInternalServerError)
		return
	}

	if groups == nil {
		groups = []models.ChatRoom{}
	}

	// 轉換為響應格式
	var groupResponses []GroupResponse
	for _, group := range groups {
		groupResponses = append(groupResponses, GroupResponse{
			ID:          group.ID.Hex(),
			Name:        group.Name,
			Description: group.Description,
			GroupType:   group.GroupType,
			MaxMembers:  group.MaxMembers,
			MemberCount: len(group.Participants),
			Admins:      group.Admins,
			CreatedBy:   group.CreatedBy,
			IsActive:    group.IsActive,
			AvatarURL:   group.AvatarURL,
			CreatedAt:   group.CreatedAt,
			UpdatedAt:   group.UpdatedAt,
		})
	}

	log.Printf("找到 %d 個用戶群組 - UserID: %s", len(groupResponses), userID)

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"groups": groupResponses,
		"count":  len(groupResponses),
	})
}

// JoinGroup 加入群組
func JoinGroup(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	// 從 JWT 中獲取用戶 ID
	userID, ok := r.Context().Value(middleware.UserIDKey).(string)
	if !ok {
		http.Error(w, `{"error": "無法獲取用戶 ID"}`, http.StatusUnauthorized)
		return
	}

	// 解析請求體
	var req JoinGroupRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		log.Printf("解析加入群組請求失敗: %v", err)
		http.Error(w, `{"error": "無效的請求格式"}`, http.StatusBadRequest)
		return
	}

	if req.GroupID == "" {
		http.Error(w, `{"error": "群組 ID 為必填項"}`, http.StatusBadRequest)
		return
	}

	log.Printf("收到加入群組請求 - UserID: %s, GroupID: %s", userID, req.GroupID)

	cfg := config.LoadConfig()
	groupCollection := database.GetCollection("chat_rooms", cfg.MongoDbName)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// 將字符串 ID 轉換為 ObjectID
	groupObjectID, err := primitive.ObjectIDFromHex(req.GroupID)
	if err != nil {
		http.Error(w, `{"error": "無效的群組 ID"}`, http.StatusBadRequest)
		return
	}

	// 查找群組
	var group models.ChatRoom
	err = groupCollection.FindOne(ctx, bson.M{"_id": groupObjectID}).Decode(&group)
	if err != nil {
		if err == mongo.ErrNoDocuments {
			http.Error(w, `{"error": "群組不存在"}`, http.StatusNotFound)
		} else {
			log.Printf("查找群組時發生錯誤: %v", err)
			http.Error(w, `{"error": "查找群組時發生錯誤"}`, http.StatusInternalServerError)
		}
		return
	}

	// 檢查群組是否活躍
	if !group.IsActive {
		http.Error(w, `{"error": "群組已停用"}`, http.StatusBadRequest)
		return
	}

	// 檢查用戶是否已經在群組中
	for _, participant := range group.Participants {
		if participant == userID {
			http.Error(w, `{"error": "您已經在此群組中"}`, http.StatusBadRequest)
			return
		}
	}

	// 檢查群組是否已滿
	if len(group.Participants) >= group.MaxMembers {
		http.Error(w, `{"error": "群組已滿"}`, http.StatusBadRequest)
		return
	}

	// 檢查群組類型
	if group.GroupType == "invite_only" {
		http.Error(w, `{"error": "此群組需要邀請才能加入"}`, http.StatusForbidden)
		return
	}

	// 將用戶添加到群組
	_, err = groupCollection.UpdateOne(
		ctx,
		bson.M{"_id": groupObjectID},
		bson.M{
			"$addToSet": bson.M{"participants": userID},
			"$set":      bson.M{"updated_at": time.Now()},
		},
	)
	if err != nil {
		log.Printf("加入群組失敗: %v", err)
		http.Error(w, `{"error": "加入群組失敗"}`, http.StatusInternalServerError)
		return
	}

	log.Printf("用戶成功加入群組 - UserID: %s, GroupID: %s", userID, req.GroupID)

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{
		"message": "成功加入群組",
	})
}

// LeaveGroup 離開群組
func LeaveGroup(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	// 從 JWT 中獲取用戶 ID
	userID, ok := r.Context().Value(middleware.UserIDKey).(string)
	if !ok {
		http.Error(w, `{"error": "無法獲取用戶 ID"}`, http.StatusUnauthorized)
		return
	}

	// 解析請求體
	var req JoinGroupRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		log.Printf("解析離開群組請求失敗: %v", err)
		http.Error(w, `{"error": "無效的請求格式"}`, http.StatusBadRequest)
		return
	}

	if req.GroupID == "" {
		http.Error(w, `{"error": "群組 ID 為必填項"}`, http.StatusBadRequest)
		return
	}

	log.Printf("收到離開群組請求 - UserID: %s, GroupID: %s", userID, req.GroupID)

	cfg := config.LoadConfig()
	groupCollection := database.GetCollection("chat_rooms", cfg.MongoDbName)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// 將字符串 ID 轉換為 ObjectID
	groupObjectID, err := primitive.ObjectIDFromHex(req.GroupID)
	if err != nil {
		http.Error(w, `{"error": "無效的群組 ID"}`, http.StatusBadRequest)
		return
	}

	// 查找群組
	var group models.ChatRoom
	err = groupCollection.FindOne(ctx, bson.M{"_id": groupObjectID}).Decode(&group)
	if err != nil {
		if err == mongo.ErrNoDocuments {
			http.Error(w, `{"error": "群組不存在"}`, http.StatusNotFound)
		} else {
			log.Printf("查找群組時發生錯誤: %v", err)
			http.Error(w, `{"error": "查找群組時發生錯誤"}`, http.StatusInternalServerError)
		}
		return
	}

	// 檢查用戶是否在群組中
	isMember := false
	for _, participant := range group.Participants {
		if participant == userID {
			isMember = true
			break
		}
	}

	if !isMember {
		http.Error(w, `{"error": "您不在此群組中"}`, http.StatusBadRequest)
		return
	}

	// 檢查是否為群組創建者
	if group.CreatedBy == userID {
		http.Error(w, `{"error": "群組創建者不能離開群組，請先轉移群組所有權或刪除群組"}`, http.StatusBadRequest)
		return
	}

	// 從群組中移除用戶
	_, err = groupCollection.UpdateOne(
		ctx,
		bson.M{"_id": groupObjectID},
		bson.M{
			"$pull": bson.M{
				"participants": userID,
				"admins":       userID,
			},
			"$set": bson.M{"updated_at": time.Now()},
		},
	)
	if err != nil {
		log.Printf("離開群組失敗: %v", err)
		http.Error(w, `{"error": "離開群組失敗"}`, http.StatusInternalServerError)
		return
	}

	log.Printf("用戶成功離開群組 - UserID: %s, GroupID: %s", userID, req.GroupID)

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{
		"message": "成功離開群組",
	})
}

// GetGroupMembers 獲取群組成員列表
func GetGroupMembers(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	// 從 JWT 中獲取用戶 ID
	userID, ok := r.Context().Value(middleware.UserIDKey).(string)
	if !ok {
		http.Error(w, `{"error": "無法獲取用戶 ID"}`, http.StatusUnauthorized)
		return
	}

	// 從 URL 參數獲取群組 ID
	groupID := r.URL.Query().Get("group_id")
	if groupID == "" {
		http.Error(w, `{"error": "群組 ID 為必填項"}`, http.StatusBadRequest)
		return
	}

	log.Printf("收到獲取群組成員請求 - UserID: %s, GroupID: %s", userID, groupID)

	cfg := config.LoadConfig()
	groupCollection := database.GetCollection("chat_rooms", cfg.MongoDbName)
	userCollection := database.GetCollection("users", cfg.MongoDbName)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// 將字符串 ID 轉換為 ObjectID
	groupObjectID, err := primitive.ObjectIDFromHex(groupID)
	if err != nil {
		http.Error(w, `{"error": "無效的群組 ID"}`, http.StatusBadRequest)
		return
	}

	// 查找群組
	var group models.ChatRoom
	err = groupCollection.FindOne(ctx, bson.M{"_id": groupObjectID}).Decode(&group)
	if err != nil {
		if err == mongo.ErrNoDocuments {
			http.Error(w, `{"error": "群組不存在"}`, http.StatusNotFound)
		} else {
			log.Printf("查找群組時發生錯誤: %v", err)
			http.Error(w, `{"error": "查找群組時發生錯誤"}`, http.StatusInternalServerError)
		}
		return
	}

	// 檢查用戶是否在群組中
	isMember := false
	for _, participant := range group.Participants {
		if participant == userID {
			isMember = true
			break
		}
	}

	if !isMember {
		http.Error(w, `{"error": "您不是此群組的成員"}`, http.StatusForbidden)
		return
	}

	// 獲取成員詳細信息
	var members []models.GroupMember
	for _, participantID := range group.Participants {
		var user models.User
		userObjectID, err := primitive.ObjectIDFromHex(participantID)
		if err != nil {
			continue
		}

		err = userCollection.FindOne(ctx, bson.M{"_id": userObjectID}).Decode(&user)
		if err != nil {
			continue
		}

		// 確定用戶角色
		role := "member"
		if participantID == group.CreatedBy {
			role = "owner"
		} else {
			for _, adminID := range group.Admins {
				if adminID == participantID {
					role = "admin"
					break
				}
			}
		}

		members = append(members, models.GroupMember{
			UserID:   participantID,
			Username: user.Username,
			Role:     role,
			JoinedAt: group.CreatedAt, // 簡化處理，實際應該記錄加入時間
			IsActive: user.IsActive,
			LastSeen: *user.LastSeen,
		})
	}

	log.Printf("找到 %d 個群組成員 - GroupID: %s", len(members), groupID)

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"members": members,
		"count":   len(members),
	})
}
