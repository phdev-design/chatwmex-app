package controllers

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"time"

	"chatwme/backend/middleware"
	"chatwme/backend/models"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
)

// InviteToGroup 邀請用戶加入群組
func InviteToGroup(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	// 從 JWT 中獲取用戶 ID
	userID, ok := r.Context().Value(middleware.UserIDKey).(string)
	if !ok {
		http.Error(w, `{"error": "無法獲取用戶 ID"}`, http.StatusUnauthorized)
		return
	}

	// 解析請求體
	var req InviteToGroupRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		log.Printf("解析邀請請求失敗: %v", err)
		http.Error(w, `{"error": "無效的請求格式"}`, http.StatusBadRequest)
		return
	}

	if req.GroupID == "" || req.InviteeEmail == "" {
		http.Error(w, `{"error": "群組 ID 和邀請郵箱為必填項"}`, http.StatusBadRequest)
		return
	}

	log.Printf("收到邀請請求 - UserID: %s, GroupID: %s, InviteeEmail: %s", userID, req.GroupID, req.InviteeEmail)

	store, ok := getStore(r)
	if !ok {
		http.Error(w, `{"error": "資料庫尚未初始化"}`, http.StatusInternalServerError)
		return
	}
	groupCollection := store.Collection("chat_rooms")
	userCollection := store.Collection("users")
	invitationCollection := store.Collection("group_invitations")
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
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

	// 檢查用戶是否為群組管理員
	isAdmin := false
	for _, adminID := range group.Admins {
		if adminID == userID {
			isAdmin = true
			break
		}
	}

	if !isAdmin && group.CreatedBy != userID {
		http.Error(w, `{"error": "只有群組管理員才能邀請成員"}`, http.StatusForbidden)
		return
	}

	// 查找被邀請用戶
	var inviteeUser models.User
	err = userCollection.FindOne(ctx, bson.M{"email": req.InviteeEmail}).Decode(&inviteeUser)
	if err != nil {
		if err == mongo.ErrNoDocuments {
			http.Error(w, `{"error": "被邀請用戶不存在"}`, http.StatusNotFound)
		} else {
			log.Printf("查找被邀請用戶時發生錯誤: %v", err)
			http.Error(w, `{"error": "查找被邀請用戶時發生錯誤"}`, http.StatusInternalServerError)
		}
		return
	}

	// 檢查用戶是否已經在群組中
	for _, participant := range group.Participants {
		if participant == inviteeUser.ID.Hex() {
			http.Error(w, `{"error": "用戶已經在此群組中"}`, http.StatusBadRequest)
			return
		}
	}

	// 檢查群組是否已滿
	if len(group.Participants) >= group.MaxMembers {
		http.Error(w, `{"error": "群組已滿"}`, http.StatusBadRequest)
		return
	}

	// 檢查是否已有待處理的邀請
	var existingInvitation models.GroupInvitation
	err = invitationCollection.FindOne(ctx, bson.M{
		"group_id":   groupObjectID,
		"invitee_id": inviteeUser.ID.Hex(),
		"status":     "pending",
	}).Decode(&existingInvitation)

	if err == nil {
		http.Error(w, `{"error": "該用戶已有待處理的邀請"}`, http.StatusBadRequest)
		return
	}

	// 創建邀請
	now := time.Now()
	invitation := models.GroupInvitation{
		ID:           primitive.NewObjectID(),
		GroupID:      groupObjectID,
		InviterID:    userID,
		InviteeID:    inviteeUser.ID.Hex(),
		InviteeEmail: req.InviteeEmail,
		Status:       "pending",
		Message:      req.Message,
		ExpiresAt:    now.Add(7 * 24 * time.Hour), // 7 天後過期
		CreatedAt:    now,
		UpdatedAt:    now,
	}

	_, err = invitationCollection.InsertOne(ctx, invitation)
	if err != nil {
		log.Printf("創建邀請失敗: %v", err)
		http.Error(w, `{"error": "創建邀請失敗"}`, http.StatusInternalServerError)
		return
	}

	log.Printf("邀請創建成功 - InvitationID: %s, GroupID: %s, InviteeID: %s",
		invitation.ID.Hex(), req.GroupID, inviteeUser.ID.Hex())

	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]string{
		"message": "邀請發送成功",
	})
}

// GetGroupInvitations 獲取群組邀請列表
func GetGroupInvitations(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	// 從 JWT 中獲取用戶 ID
	userID, ok := r.Context().Value(middleware.UserIDKey).(string)
	if !ok {
		http.Error(w, `{"error": "無法獲取用戶 ID"}`, http.StatusUnauthorized)
		return
	}

	log.Printf("收到獲取群組邀請請求 - UserID: %s", userID)

	store, ok := getStore(r)
	if !ok {
		http.Error(w, `{"error": "資料庫尚未初始化"}`, http.StatusInternalServerError)
		return
	}
	invitationCollection := store.Collection("group_invitations")
	groupCollection := store.Collection("chat_rooms")
	userCollection := store.Collection("users")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// 查詢用戶的邀請
	filter := bson.M{
		"invitee_id": userID,
		"status":     "pending",
		"expires_at": bson.M{"$gt": time.Now()}, // 未過期
	}

	cursor, err := invitationCollection.Find(ctx, filter)
	if err != nil {
		log.Printf("查詢群組邀請失敗: %v", err)
		http.Error(w, `{"error": "查詢群組邀請失敗"}`, http.StatusInternalServerError)
		return
	}
	defer cursor.Close(ctx)

	var invitations []models.GroupInvitation
	if err = cursor.All(ctx, &invitations); err != nil {
		log.Printf("解析群組邀請失敗: %v", err)
		http.Error(w, `{"error": "解析群組邀請失敗"}`, http.StatusInternalServerError)
		return
	}

	if invitations == nil {
		invitations = []models.GroupInvitation{}
	}

	// 獲取邀請詳細信息
	var invitationDetails []map[string]interface{}
	for _, invitation := range invitations {
		// 獲取群組信息
		var group models.ChatRoom
		err = groupCollection.FindOne(ctx, bson.M{"_id": invitation.GroupID}).Decode(&group)
		if err != nil {
			continue
		}

		// 獲取邀請者信息
		var inviter models.User
		inviterObjectID, err := primitive.ObjectIDFromHex(invitation.InviterID)
		if err != nil {
			continue
		}
		err = userCollection.FindOne(ctx, bson.M{"_id": inviterObjectID}).Decode(&inviter)
		if err != nil {
			continue
		}

		invitationDetails = append(invitationDetails, map[string]interface{}{
			"id":                invitation.ID.Hex(),
			"group_id":          invitation.GroupID.Hex(),
			"group_name":        group.Name,
			"group_description": group.Description,
			"inviter_id":        invitation.InviterID,
			"inviter_name":      inviter.Username,
			"message":           invitation.Message,
			"expires_at":        invitation.ExpiresAt,
			"created_at":        invitation.CreatedAt,
		})
	}

	log.Printf("找到 %d 個群組邀請 - UserID: %s", len(invitationDetails), userID)

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"invitations": invitationDetails,
		"count":       len(invitationDetails),
	})
}

// RespondToInvitation 響應群組邀請
func RespondToInvitation(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	// 從 JWT 中獲取用戶 ID
	userID, ok := r.Context().Value(middleware.UserIDKey).(string)
	if !ok {
		http.Error(w, `{"error": "無法獲取用戶 ID"}`, http.StatusUnauthorized)
		return
	}

	// 解析請求體
	var req struct {
		InvitationID string `json:"invitation_id"`
		Response     string `json:"response"` // accept, reject
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		log.Printf("解析響應邀請請求失敗: %v", err)
		http.Error(w, `{"error": "無效的請求格式"}`, http.StatusBadRequest)
		return
	}

	if req.InvitationID == "" || req.Response == "" {
		http.Error(w, `{"error": "邀請 ID 和響應為必填項"}`, http.StatusBadRequest)
		return
	}

	if req.Response != "accept" && req.Response != "reject" {
		http.Error(w, `{"error": "響應必須為 'accept' 或 'reject'"}`, http.StatusBadRequest)
		return
	}

	log.Printf("收到響應邀請請求 - UserID: %s, InvitationID: %s, Response: %s", userID, req.InvitationID, req.Response)

	store, ok := getStore(r)
	if !ok {
		http.Error(w, `{"error": "資料庫尚未初始化"}`, http.StatusInternalServerError)
		return
	}
	invitationCollection := store.Collection("group_invitations")
	groupCollection := store.Collection("chat_rooms")
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// 將字符串 ID 轉換為 ObjectID
	invitationObjectID, err := primitive.ObjectIDFromHex(req.InvitationID)
	if err != nil {
		http.Error(w, `{"error": "無效的邀請 ID"}`, http.StatusBadRequest)
		return
	}

	// 查找邀請
	var invitation models.GroupInvitation
	err = invitationCollection.FindOne(ctx, bson.M{"_id": invitationObjectID}).Decode(&invitation)
	if err != nil {
		if err == mongo.ErrNoDocuments {
			http.Error(w, `{"error": "邀請不存在"}`, http.StatusNotFound)
		} else {
			log.Printf("查找邀請時發生錯誤: %v", err)
			http.Error(w, `{"error": "查找邀請時發生錯誤"}`, http.StatusInternalServerError)
		}
		return
	}

	// 檢查邀請是否屬於當前用戶
	if invitation.InviteeID != userID {
		http.Error(w, `{"error": "無權限響應此邀請"}`, http.StatusForbidden)
		return
	}

	// 檢查邀請狀態
	if invitation.Status != "pending" {
		http.Error(w, `{"error": "邀請已經被處理"}`, http.StatusBadRequest)
		return
	}

	// 檢查邀請是否過期
	if time.Now().After(invitation.ExpiresAt) {
		http.Error(w, `{"error": "邀請已過期"}`, http.StatusBadRequest)
		return
	}

	// 更新邀請狀態
	_, err = invitationCollection.UpdateOne(
		ctx,
		bson.M{"_id": invitationObjectID},
		bson.M{
			"$set": bson.M{
				"status":     req.Response + "ed",
				"updated_at": time.Now(),
			},
		},
	)
	if err != nil {
		log.Printf("更新邀請狀態失敗: %v", err)
		http.Error(w, `{"error": "更新邀請狀態失敗"}`, http.StatusInternalServerError)
		return
	}

	// 如果用戶接受邀請，將用戶添加到群組
	if req.Response == "accept" {
		// 查找群組
		var group models.ChatRoom
		err = groupCollection.FindOne(ctx, bson.M{"_id": invitation.GroupID}).Decode(&group)
		if err != nil {
			log.Printf("查找群組時發生錯誤: %v", err)
			http.Error(w, `{"error": "查找群組時發生錯誤"}`, http.StatusInternalServerError)
			return
		}

		// 檢查群組是否已滿
		if len(group.Participants) >= group.MaxMembers {
			http.Error(w, `{"error": "群組已滿"}`, http.StatusBadRequest)
			return
		}

		// 將用戶添加到群組
		_, err = groupCollection.UpdateOne(
			ctx,
			bson.M{"_id": invitation.GroupID},
			bson.M{
				"$addToSet": bson.M{"participants": userID},
				"$set":      bson.M{"updated_at": time.Now()},
			},
		)
		if err != nil {
			log.Printf("將用戶添加到群組失敗: %v", err)
			http.Error(w, `{"error": "加入群組失敗"}`, http.StatusInternalServerError)
			return
		}

		log.Printf("用戶成功加入群組 - UserID: %s, GroupID: %s", userID, invitation.GroupID.Hex())
	}

	log.Printf("邀請響應成功 - UserID: %s, InvitationID: %s, Response: %s", userID, req.InvitationID, req.Response)

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{
		"message": "邀請響應成功",
	})
}
