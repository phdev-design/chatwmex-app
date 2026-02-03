package controllers

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"time"

	"chatwme/backend/models"
	"chatwme/backend/utils"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
)

// RefreshTokenRequest 刷新 Token 請求結構
type RefreshTokenRequest struct {
	RefreshToken string `json:"refresh_token"`
}

// RefreshTokenResponse 刷新 Token 響應結構
type RefreshTokenResponse struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token,omitempty"`
	ExpiresIn    int64  `json:"expires_in,omitempty"` // Token 有效期（秒）
}

// RefreshToken 處理 Token 刷新請求
// 端點：POST /api/v1/refresh-token
// 請求體：{"refresh_token": "..."}
// 響應：{"access_token": "...", "refresh_token": "...", "expires_in": 86400}
func RefreshToken(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	// 1. 檢查請求方法
	if r.Method != http.MethodPost {
		http.Error(w, `{"error": "只允許 POST 請求"}`, http.StatusMethodNotAllowed)
		return
	}

	// 2. 解析請求體
	var req RefreshTokenRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		log.Printf("❌ [RefreshToken] 解析請求失敗: %v", err)
		http.Error(w, `{"error": "無效的請求格式"}`, http.StatusBadRequest)
		return
	}

	// 3. 驗證 Refresh Token 是否存在
	if req.RefreshToken == "" {
		log.Printf("❌ [RefreshToken] Refresh Token 為空")
		http.Error(w, `{"error": "refresh_token 為必填項"}`, http.StatusBadRequest)
		return
	}

	log.Printf("🔄 [RefreshToken] 收到 Token 刷新請求")

	// 4. 驗證 Refresh Token
	claims, err := utils.VerifyJWT(req.RefreshToken)
	if err != nil {
		log.Printf("❌ [RefreshToken] Token 驗證失敗: %v", err)
		http.Error(w, `{"error": "無效或過期的 refresh_token"}`, http.StatusUnauthorized)
		return
	}

	// 5. 檢查 Token 發行者（可選，增加安全性）
	if claims.Issuer != "chatwme-backend-refresh" && claims.Issuer != "chatwme-backend" {
		log.Printf("❌ [RefreshToken] 無效的 Token 發行者: %s", claims.Issuer)
		http.Error(w, `{"error": "無效的 token"}`, http.StatusUnauthorized)
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

	// 6. 將字符串 ID 轉換為 ObjectID
	userObjectID, err := primitive.ObjectIDFromHex(claims.UserID)
	if err != nil {
		log.Printf("❌ [RefreshToken] 無效的用戶 ID: %s", claims.UserID)
		http.Error(w, `{"error": "無效的用戶 ID"}`, http.StatusBadRequest)
		return
	}

	// 7. 查找用戶
	var user models.User
	err = userCollection.FindOne(ctx, bson.M{"_id": userObjectID}).Decode(&user)
	if err != nil {
		if err == mongo.ErrNoDocuments {
			log.Printf("❌ [RefreshToken] 用戶不存在: %s", claims.UserID)
			http.Error(w, `{"error": "用戶不存在"}`, http.StatusNotFound)
		} else {
			log.Printf("❌ [RefreshToken] 查找用戶時發生錯誤: %v", err)
			http.Error(w, `{"error": "查找用戶時發生錯誤"}`, http.StatusInternalServerError)
		}
		return
	}

	// 8. 檢查用戶狀態
	if user.IsDeleted {
		log.Printf("❌ [RefreshToken] 用戶帳號已刪除: %s", claims.UserID)
		http.Error(w, `{"error": "用戶帳號已刪除"}`, http.StatusForbidden)
		return
	}

	if !user.IsActive {
		log.Printf("❌ [RefreshToken] 用戶帳號已停用: %s", claims.UserID)
		http.Error(w, `{"error": "用戶帳號已停用"}`, http.StatusForbidden)
		return
	}

	// 9. 生成新的 Access Token
	newAccessToken, err := utils.GenerateJWT(user.ID.Hex(), user.Username)
	if err != nil {
		log.Printf("❌ [RefreshToken] 生成 Access Token 失敗: %v", err)
		http.Error(w, `{"error": "生成 token 失敗"}`, http.StatusInternalServerError)
		return
	}

	// 10. 生成新的 Refresh Token（可選，增加安全性）
	// 建議：每次刷新都生成新的 Refresh Token，並使舊的失效
	newRefreshToken, err := utils.GenerateRefreshToken(user.ID.Hex(), user.Username)
	if err != nil {
		log.Printf("⚠️ [RefreshToken] 生成新 Refresh Token 失敗，使用舊的: %v", err)
		// 如果生成失敗，返回空字符串，前端會保留舊的
		newRefreshToken = ""
	}

	// 11. 更新用戶的最後活動時間
	_, err = userCollection.UpdateOne(
		ctx,
		bson.M{"_id": userObjectID},
		bson.M{
			"$set": bson.M{
				"last_seen":  time.Now(),
				"updated_at": time.Now(),
			},
		},
	)
	if err != nil {
		log.Printf("⚠️ [RefreshToken] 更新用戶活動時間失敗: %v", err)
		// 不返回錯誤，繼續刷新流程
	}

	log.Printf("✅ [RefreshToken] Token 刷新成功 - UserID: %s, Username: %s", claims.UserID, user.Username)

	// 12. 構建響應
	response := RefreshTokenResponse{
		AccessToken:  newAccessToken,
		RefreshToken: newRefreshToken, // 如果為空，前端會保留舊的
		ExpiresIn:    24 * 60 * 60,    // 24 小時（以秒為單位）
	}

	// 13. 返回成功響應
	w.WriteHeader(http.StatusOK)
	if err := json.NewEncoder(w).Encode(response); err != nil {
		log.Printf("❌ [RefreshToken] 編碼響應失敗: %v", err)
	}
}

// ValidateRefreshToken 驗證 Refresh Token 是否有效（輔助端點）
// 端點：POST /api/v1/validate-refresh-token
// 用於檢查 Refresh Token 是否仍然有效，不執行刷新
func ValidateRefreshToken(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	var req RefreshTokenRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error": "無效的請求格式"}`, http.StatusBadRequest)
		return
	}

	if req.RefreshToken == "" {
		http.Error(w, `{"error": "refresh_token 為必填項"}`, http.StatusBadRequest)
		return
	}

	// 驗證 Token
	claims, err := utils.VerifyJWT(req.RefreshToken)
	if err != nil {
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"valid":   false,
			"message": "Token 無效或已過期",
		})
		return
	}

	// 檢查用戶狀態
	store, ok := getStore(r)
	if !ok {
		http.Error(w, `{"error": "資料庫尚未初始化"}`, http.StatusInternalServerError)
		return
	}
	userCollection := store.Collection("users")
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	userObjectID, err := primitive.ObjectIDFromHex(claims.UserID)
	if err != nil {
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"valid":   false,
			"message": "無效的用戶 ID",
		})
		return
	}

	var user models.User
	err = userCollection.FindOne(ctx, bson.M{"_id": userObjectID}).Decode(&user)
	if err != nil || user.IsDeleted || !user.IsActive {
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"valid":   false,
			"message": "用戶不存在或已停用",
		})
		return
	}

	// Token 有效
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"valid":      true,
		"user_id":    claims.UserID,
		"username":   claims.Username,
		"expires_at": claims.ExpiresAt.Time.Format(time.RFC3339),
	})
}
