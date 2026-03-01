package controllers

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"strings"
	"time"

	"chatwme/backend/database"
	"chatwme/backend/middleware" // 如果還沒有的話
	"chatwme/backend/models"
	"chatwme/backend/utils"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

// LoginCredentials 用於解析登入請求的結構
type LoginCredentials struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

// RegisterRequest 用於解析註冊請求的結構
type RegisterRequest struct {
	Username string `json:"username"`
	Email    string `json:"email"`
	Password string `json:"password"`
	Language string `json:"language"`
}

// UserResponse 定義了返回給客戶端的使用者資訊結構，不包含密碼
type UserResponse struct {
	ID        string     `json:"id"`
	Username  string     `json:"username"`
	Email     string     `json:"email"`
	Language  string     `json:"language"`
	AvatarURL *string    `json:"avatar_url,omitempty"`
	IsOnline  bool       `json:"is_online"`
	LastSeen  *time.Time `json:"last_seen,omitempty"`
	CreatedAt time.Time  `json:"created_at"`
	UpdatedAt time.Time  `json:"updated_at"`
}

// UpdateProfileRequest 更新個人資料的請求結構
type UpdateProfileRequest struct {
	Username        *string `json:"username,omitempty"`
	Email           *string `json:"email,omitempty"`
	CurrentPassword *string `json:"current_password,omitempty"`
	NewPassword     *string `json:"new_password,omitempty"`
}

func getStore(r *http.Request) (database.Store, bool) {
	return database.StoreFromContext(r.Context())
}

// GetProfile 獲取當前用戶的個人資料
func GetProfile(w http.ResponseWriter, r *http.Request) {
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
	userCollection := store.Collection("users")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// 將字符串 ID 轉換為 ObjectID
	objectID, err := primitive.ObjectIDFromHex(userID)
	if err != nil {
		http.Error(w, `{"error": "無效的用戶 ID"}`, http.StatusBadRequest)
		return
	}

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

	// 建立並回傳一個乾淨的 UserResponse 物件
	userResponse := UserResponse{
		ID:        user.ID.Hex(),
		Username:  user.Username,
		Email:     user.Email,
		Language:  user.Language,
		AvatarURL: user.AvatarURL,
		IsOnline:  user.IsOnline,
		LastSeen:  user.LastSeen,
		CreatedAt: user.CreatedAt,
		UpdatedAt: user.UpdatedAt,
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"user": userResponse,
	})
}

// UpdateProfile 更新用戶個人資料
func UpdateProfile(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	// 從 JWT 中獲取用戶 ID
	userID, ok := r.Context().Value(middleware.UserIDKey).(string)
	if !ok {
		http.Error(w, `{"error": "無法獲取用戶 ID"}`, http.StatusUnauthorized)
		return
	}

	var req UpdateProfileRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		log.Printf("Error decoding update profile request: %v", err)
		http.Error(w, `{"error": "無效的請求格式"}`, http.StatusBadRequest)
		return
	}

	log.Printf("收到個人資料更新請求 - UserID: %s", userID)

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

	// 查找當前用戶
	var currentUser models.User
	err = userCollection.FindOne(ctx, bson.M{"_id": objectID}).Decode(&currentUser)
	if err != nil {
		if err == mongo.ErrNoDocuments {
			http.Error(w, `{"error": "用戶不存在"}`, http.StatusNotFound)
		} else {
			log.Printf("查找用戶時發生錯誤: %v", err)
			http.Error(w, `{"error": "查找用戶時發生錯誤"}`, http.StatusInternalServerError)
		}
		return
	}

	// 準備更新的字段
	updateFields := bson.M{}
	hasChanges := false

	// 檢查用戶名更新
	if req.Username != nil && *req.Username != currentUser.Username {
		*req.Username = strings.TrimSpace(*req.Username)
		if *req.Username == "" {
			http.Error(w, `{"error": "用戶名不能為空"}`, http.StatusBadRequest)
			return
		}

		// 檢查用戶名是否已被使用
		var existingUser models.User
		err = userCollection.FindOne(ctx, bson.M{
			"username": *req.Username,
			"_id":      bson.M{"$ne": objectID},
		}).Decode(&existingUser)
		if err == nil {
			http.Error(w, `{"error": "此用戶名已被使用"}`, http.StatusConflict)
			return
		} else if err != mongo.ErrNoDocuments {
			log.Printf("檢查用戶名時發生錯誤: %v", err)
			http.Error(w, `{"error": "檢查用戶名時發生錯誤"}`, http.StatusInternalServerError)
			return
		}

		updateFields["username"] = *req.Username
		hasChanges = true
		log.Printf("更新用戶名: %s -> %s", currentUser.Username, *req.Username)
	}

	// 檢查 Email 更新
	if req.Email != nil && *req.Email != currentUser.Email {
		*req.Email = strings.TrimSpace(*req.Email)
		if *req.Email == "" {
			http.Error(w, `{"error": "Email 不能為空"}`, http.StatusBadRequest)
			return
		}

		if !strings.Contains(*req.Email, "@") || !strings.Contains(*req.Email, ".") {
			http.Error(w, `{"error": "Email 格式不正確"}`, http.StatusBadRequest)
			return
		}

		// 檢查 Email 是否已被使用
		var existingUser models.User
		err = userCollection.FindOne(ctx, bson.M{
			"email": *req.Email,
			"_id":   bson.M{"$ne": objectID},
		}).Decode(&existingUser)
		if err == nil {
			http.Error(w, `{"error": "此 Email 已被使用"}`, http.StatusConflict)
			return
		} else if err != mongo.ErrNoDocuments {
			log.Printf("檢查 Email 時發生錯誤: %v", err)
			http.Error(w, `{"error": "檢查 Email 時發生錯誤"}`, http.StatusInternalServerError)
			return
		}

		updateFields["email"] = *req.Email
		hasChanges = true
		log.Printf("更新 Email: %s -> %s", currentUser.Email, *req.Email)
	}

	// 檢查密碼更新
	if req.CurrentPassword != nil && req.NewPassword != nil {
		// 驗證當前密碼
		if !utils.CheckPasswordHash(*req.CurrentPassword, currentUser.Password) {
			http.Error(w, `{"error": "當前密碼不正確"}`, http.StatusUnauthorized)
			return
		}

		// 驗證新密碼
		if len(*req.NewPassword) < 6 {
			http.Error(w, `{"error": "新密碼至少需要 6 個字符"}`, http.StatusBadRequest)
			return
		}

		// 加密新密碼
		hashedPassword, err := utils.HashPassword(*req.NewPassword)
		if err != nil {
			log.Printf("密碼加密失敗: %v", err)
			http.Error(w, `{"error": "密碼加密失敗"}`, http.StatusInternalServerError)
			return
		}

		updateFields["password"] = hashedPassword
		hasChanges = true
		log.Printf("用戶 %s 更新密碼", userID)
	}

	// 如果沒有任何變更
	if !hasChanges {
		http.Error(w, `{"error": "沒有檢測到任何變更"}`, http.StatusBadRequest)
		return
	}

	// 添加更新時間
	updateFields["updated_at"] = time.Now()

	// 執行更新
	updateResult, err := userCollection.UpdateOne(
		ctx,
		bson.M{"_id": objectID},
		bson.M{"$set": updateFields},
	)
	if err != nil {
		log.Printf("更新用戶失敗: %v", err)
		http.Error(w, `{"error": "更新個人資料失敗"}`, http.StatusInternalServerError)
		return
	}

	if updateResult.MatchedCount == 0 {
		http.Error(w, `{"error": "用戶不存在"}`, http.StatusNotFound)
		return
	}

	// 重新查詢更新後的用戶資料
	var updatedUser models.User
	err = userCollection.FindOne(ctx, bson.M{"_id": objectID}).Decode(&updatedUser)
	if err != nil {
		log.Printf("查詢更新後用戶資料失敗: %v", err)
		http.Error(w, `{"error": "查詢更新後資料失敗"}`, http.StatusInternalServerError)
		return
	}

	// 建立並回傳更新後的 UserResponse 物件
	userResponse := UserResponse{
		ID:        updatedUser.ID.Hex(),
		Username:  updatedUser.Username,
		Email:     updatedUser.Email,
		Language:  updatedUser.Language,
		AvatarURL: updatedUser.AvatarURL,
		IsOnline:  updatedUser.IsOnline,
		LastSeen:  updatedUser.LastSeen,
		CreatedAt: updatedUser.CreatedAt,
		UpdatedAt: updatedUser.UpdatedAt,
	}

	log.Printf("用戶個人資料更新成功 - UserID: %s", userID)

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"message": "個人資料更新成功",
		"user":    userResponse,
	})
}

// VerifyPassword 驗證當前密碼（可選的輔助端點）
func VerifyPassword(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	// 從 JWT 中獲取用戶 ID
	userID, ok := r.Context().Value(middleware.UserIDKey).(string)
	if !ok {
		http.Error(w, `{"error": "無法獲取用戶 ID"}`, http.StatusUnauthorized)
		return
	}

	var req struct {
		Password string `json:"password"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error": "無效的請求格式"}`, http.StatusBadRequest)
		return
	}

	if req.Password == "" {
		http.Error(w, `{"error": "密碼為必填項"}`, http.StatusBadRequest)
		return
	}

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

	var user models.User
	err = userCollection.FindOne(ctx, bson.M{"_id": objectID}).Decode(&user)
	if err != nil {
		http.Error(w, `{"error": "用戶不存在"}`, http.StatusNotFound)
		return
	}

	if !utils.CheckPasswordHash(req.Password, user.Password) {
		http.Error(w, `{"error": "密碼錯誤"}`, http.StatusUnauthorized)
		return
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{
		"message": "密碼驗證成功",
	})
}

// SearchUsers 搜尋用戶
func SearchUsers(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	query := r.URL.Query().Get("q")
	if query == "" {
		http.Error(w, `{"error": "搜尋關鍵字為必填項"}`, http.StatusBadRequest)
		return
	}

	store, ok := getStore(r)
	if !ok {
		http.Error(w, `{"error": "資料庫尚未初始化"}`, http.StatusInternalServerError)
		return
	}
	userCollection := store.Collection("users")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	filter := bson.M{
		"$or": []bson.M{
			{"username": bson.M{"$regex": query, "$options": "i"}},
			{"email": bson.M{"$regex": query, "$options": "i"}},
		},
	}

	findOptions := options.Find()
	findOptions.SetLimit(20)

	cursor, err := userCollection.Find(ctx, filter, findOptions)
	if err != nil {
		http.Error(w, `{"error": "搜尋用戶時發生錯誤"}`, http.StatusInternalServerError)
		log.Printf("Error searching users: %v", err)
		return
	}
	defer cursor.Close(ctx)

	var users []models.User
	if err = cursor.All(ctx, &users); err != nil {
		http.Error(w, `{"error": "讀取用戶資料時發生錯誤"}`, http.StatusInternalServerError)
		log.Printf("Error decoding users: %v", err)
		return
	}

	if users == nil {
		users = []models.User{}
	}

	response := map[string]interface{}{
		"users": users,
	}

	w.WriteHeader(http.StatusOK)
	if err := json.NewEncoder(w).Encode(response); err != nil {
		log.Printf("Error encoding users to JSON: %v", err)
	}
}

// Login 處理使用者登入請求
func Login(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	var creds LoginCredentials
	if err := json.NewDecoder(r.Body).Decode(&creds); err != nil {
		log.Printf("Error decoding login request: %v", err)
		http.Error(w, `{"error": "無效的請求 payload"}`, http.StatusBadRequest)
		return
	}

	creds.Email = strings.TrimSpace(creds.Email)
	creds.Password = strings.TrimSpace(creds.Password)

	if creds.Email == "" || creds.Password == "" {
		http.Error(w, `{"error": "Email 和密碼為必填項"}`, http.StatusBadRequest)
		return
	}

	log.Printf("收到登入請求 - Email: %s", creds.Email)

	store, ok := getStore(r)
	if !ok {
		http.Error(w, `{"error": "資料庫尚未初始化"}`, http.StatusInternalServerError)
		return
	}
	userCollection := store.Collection("users")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	var user models.User
	err := userCollection.FindOne(ctx, bson.M{"email": creds.Email}).Decode(&user)
	if err != nil {
		if err == mongo.ErrNoDocuments {
			log.Printf("用戶不存在: %s", creds.Email)
		} else {
			log.Printf("查找用戶時發生錯誤: %v", err)
		}
		http.Error(w, `{"error": "無效的 Email 或密碼"}`, http.StatusUnauthorized)
		return
	}

	if !utils.CheckPasswordHash(creds.Password, user.Password) {
		log.Printf("密碼驗證失敗 - Email: %s", creds.Email)
		http.Error(w, `{"error": "無效的 Email 或密碼"}`, http.StatusUnauthorized)
		return
	}

	// 生成 Access Token (7天)
	accessToken, err := utils.GenerateJWT(user.ID.Hex(), user.Username)
	if err != nil {
		log.Printf("無法生成 access token: %v", err)
		http.Error(w, `{"error": "無法生成 token"}`, http.StatusInternalServerError)
		return
	}

	// 生成 Refresh Token (7天)
	refreshToken, err := utils.GenerateRefreshToken(user.ID.Hex(), user.Username)
	if err != nil {
		log.Printf("無法生成 refresh token: %v", err)
		http.Error(w, `{"error": "無法生成 token"}`, http.StatusInternalServerError)
		return
	}

	// 提取設備信息
	deviceInfo := utils.ExtractDeviceInfo(r)
	log.Printf("設備信息 - IP: %s, 設備: %s, 系統: %s, 瀏覽器: %s",
		deviceInfo.IPAddress, deviceInfo.DeviceType, deviceInfo.OS, deviceInfo.Browser)

	// 創建設備信息記錄
	deviceInfoModel := utils.CreateDeviceInfoModel(user.ID, deviceInfo)

	// 創建登入會話
	loginSession := utils.CreateLoginSession(user.ID, deviceInfo, accessToken)

	// 保存設備信息到數據庫
	deviceCollection := store.Collection("device_info")
	_, err = deviceCollection.InsertOne(ctx, deviceInfoModel)
	if err != nil {
		log.Printf("保存設備信息失敗: %v", err)
		// 不返回錯誤，繼續登入流程
	}

	// 保存登入會話到數據庫
	sessionCollection := store.Collection("login_sessions")
	_, err = sessionCollection.InsertOne(ctx, loginSession)
	if err != nil {
		log.Printf("保存登入會話失敗: %v", err)
		// 不返回錯誤，繼續登入流程
	}

	// 更新用戶在線狀態
	_, err = userCollection.UpdateOne(
		ctx,
		bson.M{"_id": user.ID},
		bson.M{
			"$set": bson.M{
				"is_online":  true,
				"last_seen":  time.Now(),
				"updated_at": time.Now(),
			},
		},
	)
	if err != nil {
		log.Printf("更新用戶在線狀態失敗: %v", err)
		// 不返回錯誤，繼續登入流程
	}

	log.Printf("用戶登入成功 - Email: %s, IP: %s, 設備: %s",
		creds.Email, deviceInfo.IPAddress, deviceInfo.DeviceType)

	// [修正] 建立並回傳一個乾淨的 UserResponse 物件
	userResponse := UserResponse{
		ID:        user.ID.Hex(),
		Username:  user.Username,
		Email:     user.Email,
		Language:  user.Language,
		AvatarURL: user.AvatarURL,
		IsOnline:  user.IsOnline,
		LastSeen:  user.LastSeen,
		CreatedAt: user.CreatedAt,
		UpdatedAt: user.UpdatedAt,
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"message":       "登入成功",
		"access_token":  accessToken,  // 🔥 改名
		"refresh_token": refreshToken, // 🔥 新增
		"user":          userResponse,
	})
}

// RegisterUser 處理使用者註冊的請求
func RegisterUser(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	var req RegisterRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		log.Printf("Error decoding register request: %v", err)
		http.Error(w, `{"error": "無效的請求 payload"}`, http.StatusBadRequest)
		return
	}

	req.Username = strings.TrimSpace(req.Username)
	req.Email = strings.TrimSpace(req.Email)
	req.Language = strings.TrimSpace(req.Language)

	log.Printf("收到註冊請求 - Username: %s, Email: %s, Language: %s",
		req.Username, req.Email, req.Language)

	if req.Username == "" || req.Email == "" || req.Password == "" || req.Language == "" {
		http.Error(w, `{"error": "所有欄位皆為必填項"}`, http.StatusBadRequest)
		return
	}

	if !strings.Contains(req.Email, "@") || !strings.Contains(req.Email, ".") {
		log.Printf("Email 格式不正確: %s", req.Email)
		http.Error(w, `{"error": "Email 格式不正確"}`, http.StatusBadRequest)
		return
	}

	if len(req.Password) < 6 {
		log.Printf("密碼太短: %d 字符", len(req.Password))
		http.Error(w, `{"error": "密碼至少需要 6 個字符"}`, http.StatusBadRequest)
		return
	}

	store, ok := getStore(r)
	if !ok {
		http.Error(w, `{"error": "資料庫尚未初始化"}`, http.StatusInternalServerError)
		return
	}
	userCollection := store.Collection("users")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	var existingUser models.User
	err := userCollection.FindOne(ctx, bson.M{"email": req.Email}).Decode(&existingUser)
	if err == nil {
		log.Printf("Email 已存在: %s", req.Email)
		http.Error(w, `{"error": "此 Email 已經被註冊"}`, http.StatusConflict)
		return
	} else if err != mongo.ErrNoDocuments {
		log.Printf("檢查 Email 時發生錯誤: %v", err)
		http.Error(w, `{"error": "檢查 email 時發生錯誤"}`, http.StatusInternalServerError)
		return
	}

	err = userCollection.FindOne(ctx, bson.M{"username": req.Username}).Decode(&existingUser)
	if err == nil {
		log.Printf("用戶名稱已存在: %s", req.Username)
		http.Error(w, `{"error": "此用戶名稱已被使用"}`, http.StatusConflict)
		return
	} else if err != mongo.ErrNoDocuments {
		log.Printf("檢查用戶名稱時發生錯誤: %v", err)
		http.Error(w, `{"error": "檢查用戶名稱時發生錯誤"}`, http.StatusInternalServerError)
		return
	}

	hashedPassword, err := utils.HashPassword(req.Password)
	if err != nil {
		log.Printf("密碼加密失敗: %v", err)
		http.Error(w, `{"error": "密碼加密失敗"}`, http.StatusInternalServerError)
		return
	}

	// [修正] 創建新使用者時，初始化所有狀態字段
	newUser := models.User{
		ID:        primitive.NewObjectID(),
		Username:  req.Username,
		Email:     req.Email,
		Password:  hashedPassword,
		Language:  req.Language,
		IsOnline:  false, // 預設為離線
		LastSeen:  nil,   // 預設為空
		IsActive:  true,  // 預設為活躍
		IsDeleted: false, // 預設為未刪除
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}

	result, err := userCollection.InsertOne(ctx, newUser)
	if err != nil {
		log.Printf("插入用戶失敗: %v", err)
		http.Error(w, `{"error": "建立使用者失敗"}`, http.StatusInternalServerError)
		return
	}

	log.Printf("用戶註冊成功 - ID: %v, Username: %s", result.InsertedID, req.Username)

	response := map[string]interface{}{
		"message":    "註冊成功",
		"user_id":    result.InsertedID,
		"username":   req.Username,
		"email":      req.Email,
		"language":   req.Language,
		"created_at": newUser.CreatedAt,
	}

	w.WriteHeader(http.StatusCreated)
	if err := json.NewEncoder(w).Encode(response); err != nil {
		log.Printf("編碼響應失敗: %v", err)
	}
}
