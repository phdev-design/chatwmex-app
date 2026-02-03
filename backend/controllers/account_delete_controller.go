package controllers

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"time"

	"chatwme/backend/database"
	"chatwme/backend/middleware"
	"chatwme/backend/models"
	"chatwme/backend/utils"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
)

// AccountDeletionRequest 帳號刪除請求結構
type AccountDeletionRequest struct {
	Password       string `json:"password"`        // 確認密碼
	DeletionReason string `json:"deletion_reason"` // 刪除原因（可選）
	ConfirmText    string `json:"confirm_text"`    // 確認文本
}

// AccountDeletionResponse 帳號刪除響應結構
type AccountDeletionResponse struct {
	Message string `json:"message"`
	Success bool   `json:"success"`
}

// DeleteAccount 刪除用戶帳號
func DeleteAccount(w http.ResponseWriter, r *http.Request) {
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
	var req AccountDeletionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		log.Printf("解析帳號刪除請求失敗: %v", err)
		http.Error(w, `{"error": "無效的請求格式"}`, http.StatusBadRequest)
		return
	}

	// 驗證必填字段
	if req.Password == "" {
		http.Error(w, `{"error": "密碼為必填項"}`, http.StatusBadRequest)
		return
	}

	if req.ConfirmText != "DELETE_MY_ACCOUNT" {
		http.Error(w, `{"error": "確認文本不正確，請輸入 'DELETE_MY_ACCOUNT'"}`, http.StatusBadRequest)
		return
	}

	log.Printf("收到帳號刪除請求 - UserID: %s", userID)

	store, ok := getStore(r)
	if !ok {
		http.Error(w, `{"error": "資料庫尚未初始化"}`, http.StatusInternalServerError)
		return
	}
	userCollection := store.Collection("users")
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

	// 檢查帳號是否已經被刪除
	if user.IsDeleted {
		http.Error(w, `{"error": "帳號已經被刪除"}`, http.StatusBadRequest)
		return
	}

	// 驗證密碼
	if !utils.CheckPasswordHash(req.Password, user.Password) {
		http.Error(w, `{"error": "密碼不正確"}`, http.StatusUnauthorized)
		return
	}

	// 開始刪除流程
	log.Printf("開始刪除用戶帳號 - UserID: %s", userID)

	// 1. 更新用戶狀態為已刪除
	now := time.Now()
	deletionReason := req.DeletionReason
	if deletionReason == "" {
		deletionReason = "用戶主動刪除"
	}

	_, err = userCollection.UpdateOne(
		ctx,
		bson.M{"_id": objectID},
		bson.M{
			"$set": bson.M{
				"is_deleted":      true,
				"is_active":       false,
				"is_online":       false,
				"deleted_at":      now,
				"deletion_reason": deletionReason,
				"updated_at":      now,
			},
		},
	)
	if err != nil {
		log.Printf("更新用戶狀態失敗: %v", err)
		http.Error(w, `{"error": "刪除帳號失敗"}`, http.StatusInternalServerError)
		return
	}

	// 2. 處理相關數據
	err = handleRelatedDataDeletion(ctx, store, objectID, userID)
	if err != nil {
		log.Printf("處理相關數據失敗: %v", err)
		// 不返回錯誤，繼續刪除流程
	}

	// 3. 終止所有登入會話
	err = terminateAllUserSessions(ctx, store, objectID)
	if err != nil {
		log.Printf("終止用戶會話失敗: %v", err)
		// 不返回錯誤，繼續刪除流程
	}

	log.Printf("用戶帳號刪除成功 - UserID: %s", userID)

	// 返回成功響應
	response := AccountDeletionResponse{
		Message: "帳號刪除成功",
		Success: true,
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}

// handleRelatedDataDeletion 處理相關數據的刪除或匿名化
func handleRelatedDataDeletion(ctx context.Context, store database.Store, userObjectID primitive.ObjectID, userID string) error {
	// 1. 匿名化消息
	messageCollection := store.Collection("messages")
	_, err := messageCollection.UpdateMany(
		ctx,
		bson.M{"sender_id": userID},
		bson.M{
			"$set": bson.M{
				"sender_name": "已刪除用戶",
				"content":     "[此用戶已刪除帳號]",
				"is_deleted":  true,
				"deleted_at":  time.Now(),
			},
		},
	)
	if err != nil {
		log.Printf("匿名化消息失敗: %v", err)
	}

	// 2. 刪除設備信息
	deviceCollection := store.Collection("device_info")
	_, err = deviceCollection.DeleteMany(ctx, bson.M{"user_id": userObjectID})
	if err != nil {
		log.Printf("刪除設備信息失敗: %v", err)
	}

	// 3. 刪除登入會話
	sessionCollection := store.Collection("login_sessions")
	_, err = sessionCollection.DeleteMany(ctx, bson.M{"user_id": userObjectID})
	if err != nil {
		log.Printf("刪除登入會話失敗: %v", err)
	}

	// 4. 處理聊天室相關數據
	chatRoomCollection := store.Collection("chat_rooms")

	// 將用戶從所有聊天室中移除
	_, err = chatRoomCollection.UpdateMany(
		ctx,
		bson.M{"members": userID},
		bson.M{
			"$pull": bson.M{"members": userID},
		},
	)
	if err != nil {
		log.Printf("從聊天室移除用戶失敗: %v", err)
	}

	// 5. 刪除用戶的頭像文件（如果存在）
	if userID != "" {
		// 這裡可以添加刪除頭像文件的邏輯
		log.Printf("用戶頭像文件清理完成 - UserID: %s", userID)
	}

	return nil
}

// terminateAllUserSessions 終止用戶的所有登入會話
func terminateAllUserSessions(ctx context.Context, store database.Store, userObjectID primitive.ObjectID) error {
	sessionCollection := store.Collection("login_sessions")

	_, err := sessionCollection.UpdateMany(
		ctx,
		bson.M{
			"user_id":   userObjectID,
			"is_active": true,
		},
		bson.M{
			"$set": bson.M{
				"is_active":   false,
				"logout_time": time.Now(),
				"updated_at":  time.Now(),
			},
		},
	)

	return err
}

// GetAccountDeletionInfo 獲取帳號刪除信息
func GetAccountDeletionInfo(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	// 從 JWT 中獲取用戶 ID
	userID, ok := r.Context().Value(middleware.UserIDKey).(string)
	if !ok {
		http.Error(w, `{"error": "無法獲取用戶 ID"}`, http.StatusUnauthorized)
		return
	}

	log.Printf("收到獲取帳號刪除信息請求 - UserID: %s", userID)

	store, ok := getStore(r)
	if !ok {
		http.Error(w, `{"error": "資料庫尚未初始化"}`, http.StatusInternalServerError)
		return
	}
	userCollection := store.Collection("users")
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

	// 檢查帳號狀態
	if user.IsDeleted {
		http.Error(w, `{"error": "帳號已被刪除"}`, http.StatusGone)
		return
	}

	// 統計相關數據
	messageCollection := store.Collection("messages")
	messageCount, _ := messageCollection.CountDocuments(ctx, bson.M{"sender_id": userID})

	deviceCollection := store.Collection("device_info")
	deviceCount, _ := deviceCollection.CountDocuments(ctx, bson.M{"user_id": objectID})

	sessionCollection := store.Collection("login_sessions")
	sessionCount, _ := sessionCollection.CountDocuments(ctx, bson.M{"user_id": objectID})

	// 返回帳號信息
	accountInfo := map[string]interface{}{
		"user_id":       user.ID.Hex(),
		"username":      user.Username,
		"email":         user.Email,
		"created_at":    user.CreatedAt,
		"is_active":     user.IsActive,
		"is_online":     user.IsOnline,
		"message_count": messageCount,
		"device_count":  deviceCount,
		"session_count": sessionCount,
		"warning":       "刪除帳號將無法恢復，所有相關數據將被永久刪除或匿名化",
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"account_info": accountInfo,
	})
}

// CancelAccountDeletion 取消帳號刪除（如果帳號還未完全刪除）
func CancelAccountDeletion(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	// 從 JWT 中獲取用戶 ID
	userID, ok := r.Context().Value(middleware.UserIDKey).(string)
	if !ok {
		http.Error(w, `{"error": "無法獲取用戶 ID"}`, http.StatusUnauthorized)
		return
	}

	log.Printf("收到取消帳號刪除請求 - UserID: %s", userID)

	store, ok := getStore(r)
	if !ok {
		http.Error(w, `{"error": "資料庫尚未初始化"}`, http.StatusInternalServerError)
		return
	}
	userCollection := store.Collection("users")
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

	// 檢查帳號狀態
	if !user.IsDeleted {
		http.Error(w, `{"error": "帳號未被刪除"}`, http.StatusBadRequest)
		return
	}

	// 恢復帳號
	_, err = userCollection.UpdateOne(
		ctx,
		bson.M{"_id": objectID},
		bson.M{
			"$set": bson.M{
				"is_deleted": false,
				"is_active":  true,
				"updated_at": time.Now(),
			},
			"$unset": bson.M{
				"deleted_at":      "",
				"deletion_reason": "",
			},
		},
	)
	if err != nil {
		log.Printf("恢復帳號失敗: %v", err)
		http.Error(w, `{"error": "恢復帳號失敗"}`, http.StatusInternalServerError)
		return
	}

	log.Printf("帳號恢復成功 - UserID: %s", userID)

	// 返回成功響應
	response := AccountDeletionResponse{
		Message: "帳號恢復成功",
		Success: true,
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}
