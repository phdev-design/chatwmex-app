package routes

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"time"

	"chatwme/backend/controllers"
	"chatwme/backend/database"
	"chatwme/backend/middleware"
	"chatwme/backend/models"

	"github.com/gorilla/mux"
	"go.mongodb.org/mongo-driver/bson"
)

// getUsersHandler 從資料庫獲取使用者列表
func getUsersHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	// 載入設定以取得資料庫名稱
	store, ok := database.StoreFromContext(r.Context())
	if !ok {
		http.Error(w, `{"error": "資料庫尚未初始化"}`, http.StatusInternalServerError)
		return
	}
	userCollection := store.Collection("users")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// 查找所有使用者
	cursor, err := userCollection.Find(ctx, bson.M{})
	if err != nil {
		http.Error(w, `{"error": "查詢使用者時發生錯誤"}`, http.StatusInternalServerError)
		log.Printf("Error finding users: %v", err)
		return
	}
	defer cursor.Close(ctx)

	var users []models.User
	// 遍歷查詢結果
	if err = cursor.All(ctx, &users); err != nil {
		http.Error(w, `{"error": "讀取使用者資料時發生錯誤"}`, http.StatusInternalServerError)
		log.Printf("Error decoding users: %v", err)
		return
	}

	// 如果沒有找到使用者，返回一個空陣列
	if users == nil {
		users = []models.User{}
	}

	// 成功，回傳使用者列表
	w.WriteHeader(http.StatusOK)
	if err := json.NewEncoder(w).Encode(users); err != nil {
		log.Printf("Error encoding users to JSON: %v", err)
	}
}

// SetupUserRoutes 設定所有與使用者相關的路由
func SetupUserRoutes(router *mux.Router) {
	// 不需要認證的路由
	router.HandleFunc("/register", controllers.RegisterUser).Methods("POST")
	router.HandleFunc("/login", controllers.Login).Methods("POST")

	// 需要認證的用戶路由
	userRouter := router.PathPrefix("/users").Subrouter()
	userRouter.Use(middleware.JwtAuthentication)
	
	userRouter.HandleFunc("", getUsersHandler).Methods("GET")
	userRouter.HandleFunc("/search", controllers.SearchUsers).Methods("GET")

	// === 新增：個人資料相關路由 ===
	// 創建個人資料子路由器，需要認證
	profileRouter := router.PathPrefix("/profile").Subrouter()
	profileRouter.Use(middleware.JwtAuthentication)
	
	// 獲取當前用戶個人資料
	profileRouter.HandleFunc("", controllers.GetProfile).Methods("GET")
	
	// 更新個人資料
	profileRouter.HandleFunc("", controllers.UpdateProfile).Methods("PUT")
	
	// 驗證密碼路由（可選）
	verifyRouter := router.PathPrefix("/verify-password").Subrouter()
	verifyRouter.Use(middleware.JwtAuthentication)
	verifyRouter.HandleFunc("", controllers.VerifyPassword).Methods("POST")
}
