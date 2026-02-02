package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"chatwme/backend/config"
	"chatwme/backend/database"
	"chatwme/backend/routes"
	"chatwme/backend/websockets"
)

func main() {
	// 1. 載入設定
	cfg := config.LoadConfig()

	// 創建必要的上傳目錄
	uploadPath := os.Getenv("UPLOAD_PATH")
	if uploadPath == "" {
		uploadPath = "./uploads"
	}

	// 創建目錄結構
	dirs := []string{
		filepath.Join(uploadPath, "audio"),
		filepath.Join(uploadPath, "avatars"),
	}

	for _, dir := range dirs {
		if err := os.MkdirAll(dir, 0777); err != nil {
			log.Printf("Warning: Could not create directory %s: %v", dir, err)
		} else {
			log.Printf("✓ Created directory: %s", dir)
		}
	}

	// 在啟動時印出版本號和配置信息
	log.Printf("=== Starting ChatwMeX Server ===")
	log.Printf("Version: %s", cfg.AppVersion)
	log.Printf("Environment: %s", cfg.Environment)
	log.Printf("Server Port: %s", cfg.ServerPort)
	log.Printf("MongoDB Database: %s", cfg.MongoDbName)
	log.Printf("Storage Base URL: %s", cfg.StorageBaseURL)
	log.Printf("Use Cloudflare: %t", cfg.UseCloudflare)
	log.Printf("Upload Path: %s", uploadPath)
	log.Printf("================================")

	// 2. 連線到資料庫
	if err := database.ConnectDB(cfg.MongoURI); err != nil {
		log.Fatalf("Could not connect to MongoDB: %v", err)
	}
	log.Println("✓ MongoDB connected successfully")

	// 應用程式結束時斷開資料庫連線
	defer database.DisconnectDB()

	// 3. 初始化 Socket.IO 伺服器
	log.Println("Initializing Socket.IO server...")
	socketServer := websockets.NewSocketIOServer()

	// 啟動 Socket.IO 伺服器
	go func() {
		log.Println("Starting Socket.IO server...")
		if err := socketServer.Serve(); err != nil {
			log.Fatalf("Socket.IO listen error: %s\n", err)
		}
	}()
	defer socketServer.Close()
	log.Println("✓ Socket.IO server initialized")

	// 4. 初始化 HTTP API 路由
	log.Println("Setting up HTTP routes...")
	apiHandler := routes.SetupRoutes()
	log.Println("✓ HTTP routes configured")

	// 5. 設定 HTTP 伺服器
	mux := http.NewServeMux()
	mux.Handle("/socket.io/", socketServer) // 將 /socket.io/ 路徑交給 Socket.IO 處理
	mux.Handle("/", apiHandler)             // 將所有其他請求交給我們帶有 CORS 的路由器處理

	// 6. 優雅地啟動與關閉伺服器
	server := &http.Server{
		Addr:         cfg.ServerPort,
		Handler:      mux,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	go func() {
		log.Printf("🚀 Server is ready and listening on port %s", cfg.ServerPort)
		log.Printf("📡 Socket.IO endpoint: http://localhost%s/socket.io/", cfg.ServerPort)
		log.Printf("🌐 API endpoint: http://localhost%s/api/v1/", cfg.ServerPort)
		log.Println("Press Ctrl+C to shutdown")

		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Could not listen on %s: %v\n", cfg.ServerPort, err)
		}
	}()

	// 等待中斷訊號
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("🛑 Shutting down server...")

	// 給予 5 秒的時間來處理現有請求
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := server.Shutdown(ctx); err != nil {
		log.Fatalf("Server forced to shutdown: %v", err)
	}

	log.Println("✓ Server exited gracefully")
}
