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
	"go.mongodb.org/mongo-driver/mongo/options"
)

// GetUserDevices 獲取用戶的設備列表
func GetUserDevices(w http.ResponseWriter, r *http.Request) {
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
	deviceCollection := store.Collection("device_info")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// 將字符串 ID 轉換為 ObjectID
	objectID, err := primitive.ObjectIDFromHex(userID)
	if err != nil {
		http.Error(w, `{"error": "無效的用戶 ID"}`, http.StatusBadRequest)
		return
	}

	// 查詢用戶的設備信息
	filter := bson.M{"user_id": objectID}
	findOptions := options.Find().SetSort(bson.M{"login_time": -1}) // 按登入時間倒序

	cursor, err := deviceCollection.Find(ctx, filter, findOptions)
	if err != nil {
		log.Printf("查詢設備信息失敗: %v", err)
		http.Error(w, `{"error": "查詢設備信息失敗"}`, http.StatusInternalServerError)
		return
	}
	defer cursor.Close(ctx)

	var devices []models.DeviceInfo
	if err = cursor.All(ctx, &devices); err != nil {
		log.Printf("解析設備信息失敗: %v", err)
		http.Error(w, `{"error": "解析設備信息失敗"}`, http.StatusInternalServerError)
		return
	}

	if devices == nil {
		devices = []models.DeviceInfo{}
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"devices": devices,
		"count":   len(devices),
	})
}

// GetUserSessions 獲取用戶的登入會話
func GetUserSessions(w http.ResponseWriter, r *http.Request) {
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
	sessionCollection := store.Collection("login_sessions")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// 將字符串 ID 轉換為 ObjectID
	objectID, err := primitive.ObjectIDFromHex(userID)
	if err != nil {
		http.Error(w, `{"error": "無效的用戶 ID"}`, http.StatusBadRequest)
		return
	}

	// 查詢用戶的登入會話
	filter := bson.M{"user_id": objectID}
	findOptions := options.Find().SetSort(bson.M{"login_time": -1}) // 按登入時間倒序

	cursor, err := sessionCollection.Find(ctx, filter, findOptions)
	if err != nil {
		log.Printf("查詢登入會話失敗: %v", err)
		http.Error(w, `{"error": "查詢登入會話失敗"}`, http.StatusInternalServerError)
		return
	}
	defer cursor.Close(ctx)

	var sessions []models.LoginSession
	if err = cursor.All(ctx, &sessions); err != nil {
		log.Printf("解析登入會話失敗: %v", err)
		http.Error(w, `{"error": "解析登入會話失敗"}`, http.StatusInternalServerError)
		return
	}

	if sessions == nil {
		sessions = []models.LoginSession{}
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"sessions": sessions,
		"count":    len(sessions),
	})
}

// TerminateSession 終止指定的登入會話
func TerminateSession(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	// 從 JWT 中獲取用戶 ID
	userID, ok := r.Context().Value(middleware.UserIDKey).(string)
	if !ok {
		http.Error(w, `{"error": "無法獲取用戶 ID"}`, http.StatusUnauthorized)
		return
	}

	// 從 URL 參數獲取會話 ID
	sessionID := r.URL.Query().Get("session_id")
	if sessionID == "" {
		http.Error(w, `{"error": "會話 ID 為必填項"}`, http.StatusBadRequest)
		return
	}

	store, ok := getStore(r)
	if !ok {
		http.Error(w, `{"error": "資料庫尚未初始化"}`, http.StatusInternalServerError)
		return
	}
	sessionCollection := store.Collection("login_sessions")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// 將字符串 ID 轉換為 ObjectID
	userObjectID, err := primitive.ObjectIDFromHex(userID)
	if err != nil {
		http.Error(w, `{"error": "無效的用戶 ID"}`, http.StatusBadRequest)
		return
	}

	sessionObjectID, err := primitive.ObjectIDFromHex(sessionID)
	if err != nil {
		http.Error(w, `{"error": "無效的會話 ID"}`, http.StatusBadRequest)
		return
	}

	// 更新會話狀態
	updateResult, err := sessionCollection.UpdateOne(
		ctx,
		bson.M{
			"_id":     sessionObjectID,
			"user_id": userObjectID,
		},
		bson.M{
			"$set": bson.M{
				"is_active":   false,
				"logout_time": time.Now(),
				"updated_at":  time.Now(),
			},
		},
	)
	if err != nil {
		log.Printf("終止會話失敗: %v", err)
		http.Error(w, `{"error": "終止會話失敗"}`, http.StatusInternalServerError)
		return
	}

	if updateResult.MatchedCount == 0 {
		http.Error(w, `{"error": "會話不存在或無權限"}`, http.StatusNotFound)
		return
	}

	log.Printf("會話終止成功 - UserID: %s, SessionID: %s", userID, sessionID)

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{
		"message": "會話終止成功",
	})
}

// GetCurrentSession 獲取當前會話信息
func GetCurrentSession(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	// 從 JWT 中獲取用戶 ID
	userID, ok := r.Context().Value(middleware.UserIDKey).(string)
	if !ok {
		http.Error(w, `{"error": "無法獲取用戶 ID"}`, http.StatusUnauthorized)
		return
	}

	// 從 Authorization 標頭獲取 token
	authHeader := r.Header.Get("Authorization")
	if authHeader == "" {
		http.Error(w, `{"error": "未找到認證標頭"}`, http.StatusUnauthorized)
		return
	}

	// 提取 token
	tokenString := authHeader[7:] // 跳過 "Bearer "

	store, ok := getStore(r)
	if !ok {
		http.Error(w, `{"error": "資料庫尚未初始化"}`, http.StatusInternalServerError)
		return
	}
	sessionCollection := store.Collection("login_sessions")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// 將字符串 ID 轉換為 ObjectID
	objectID, err := primitive.ObjectIDFromHex(userID)
	if err != nil {
		http.Error(w, `{"error": "無效的用戶 ID"}`, http.StatusBadRequest)
		return
	}

	// 查詢當前會話
	var session models.LoginSession
	err = sessionCollection.FindOne(ctx, bson.M{
		"user_id":       objectID,
		"session_token": tokenString,
		"is_active":     true,
	}).Decode(&session)
	if err != nil {
		if err == mongo.ErrNoDocuments {
			http.Error(w, `{"error": "會話不存在或已過期"}`, http.StatusNotFound)
		} else {
			log.Printf("查詢當前會話失敗: %v", err)
			http.Error(w, `{"error": "查詢當前會話失敗"}`, http.StatusInternalServerError)
		}
		return
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"session": session,
	})
}
