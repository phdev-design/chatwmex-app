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

	"chatwmex_backend/internal/config"
	delivery "chatwmex_backend/internal/delivery/http"
	"chatwmex_backend/internal/delivery/http/middleware"
	"chatwmex_backend/internal/delivery/websocket"
	"chatwmex_backend/internal/domain"
	"chatwmex_backend/internal/infrastructure"
	"chatwmex_backend/internal/infrastructure/notification"
	"chatwmex_backend/internal/infrastructure/rabbitmq"
	"chatwmex_backend/internal/repository/mongo_repo"
	"chatwmex_backend/internal/repository/redis_repo"
	"chatwmex_backend/internal/usecase"

	"github.com/gin-gonic/gin"
)

func main() {
	// 1. Load Configuration
	cfg, err := config.LoadConfig()
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	// 2. Initialize Infrastructure
	// MongoDB Connection
	db, err := infrastructure.NewMongoClient(cfg)
	if err != nil {
		log.Fatalf("Failed to connect to MongoDB: %v", err)
	}
	// Ensure graceful disconnection when main exits
	defer func() {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := db.Client().Disconnect(ctx); err != nil {
			log.Printf("Error disconnecting from MongoDB: %v", err)
		} else {
			log.Println("Disconnected from MongoDB")
		}
	}()

	// Redis Connection
	redisClient, err := infrastructure.NewRedisClient(cfg)
	if err != nil {
		// Log warning but don't fail, to allow running without Redis if needed (or make it fatal)
		log.Printf("Warning: Failed to connect to Redis: %v", err)
	} else {
		defer func() {
			if err := redisClient.Close(); err != nil {
				log.Printf("Error closing Redis: %v", err)
			}
		}()
	}

	// 3. Initialize Repositories
	userRepo := mongo_repo.NewUserRepository(db)
	messageRepo := mongo_repo.NewMessageRepository(db)
	roomRepo := mongo_repo.NewRoomRepository(db)
	friendRepo := mongo_repo.NewFriendRepository(db)
	deviceRepo := mongo_repo.NewDeviceRepository(db)
	onlineRepo := redis_repo.NewOnlineRepository(redisClient)
	chatSettingRepo := mongo_repo.NewChatSettingRepository(db) // 👉 新增

	// 4. Initialize Usecases
	// Set a default timeout for usecase operations
	timeout := 5 * time.Second
	userUsecase := usecase.NewUserUsecase(userRepo, timeout)
	chatSettingUsecase := usecase.NewChatSettingUsecase(chatSettingRepo) // 👉 新增
	// Initialize Notification Service
	// If OneSignal config is missing, use a mock or nil.
	// We require it for "Push Notification" feature.
	var notificationService domain.NotificationService
	if cfg.OneSignalAppID != "" && cfg.OneSignalAPIKey != "" {
		notificationService = notification.NewOneSignalService(cfg.OneSignalAppID, cfg.OneSignalAPIKey)
	} else {
		log.Println("Warning: OneSignal config missing, push notifications will be disabled")
		// Ideally use a no-op mock
	}

	var pushService domain.PushNotificationService
	if notificationService != nil {
		if ps, ok := notificationService.(domain.PushNotificationService); ok {
			pushService = ps
		}
	}
	messageUsecase := usecase.NewMessageUsecase(
		messageRepo,
		roomRepo,
		onlineRepo,
		userRepo,
		deviceRepo,
		pushService,
		chatSettingUsecase, // 👉 加入參數
		redisClient,
		timeout,
	)
	roomUsecase := usecase.NewRoomUsecase(roomRepo, messageRepo, timeout)
	deviceUsecase := usecase.NewDeviceUsecase(deviceRepo, timeout)

	// 5. Initialize HTTP Server
	if cfg.AppEnv == "release" {
		gin.SetMode(gin.ReleaseMode)
	}
	r := gin.Default()
	uploadsRootDir := filepath.Join("cmd", "server", "uploads")
	if err := os.MkdirAll(filepath.Join(uploadsRootDir, "avatars"), 0o755); err != nil {
		log.Fatalf("failed to create uploads directory: %v", err)
	}
	if err := os.MkdirAll(filepath.Join(uploadsRootDir, "images"), 0o755); err != nil {
		log.Fatalf("failed to create uploads directory: %v", err)
	}
	if err := os.MkdirAll(filepath.Join(uploadsRootDir, "audio"), 0o755); err != nil {
		log.Fatalf("failed to create uploads directory: %v", err)
	}
	r.Static("/uploads", uploadsRootDir)

	// 6. Initialize Handlers & Routes
	// Setup Auth Middleware
	// Ensure JWT Secret is set
	if cfg.JWTSecret == "" {
		log.Println("Warning: JWT_SECRET is not set, using a default (unsafe) secret for dev only")
		cfg.JWTSecret = "default-dev-secret-do-not-use-in-prod"
	}
	authMiddleware := middleware.AuthMiddleware(cfg.JWTSecret)

	// Initialize WebSocket Hub
	rabbitIn := make(chan *domain.Message)
	rabbitEvents := make(chan []byte)

	var rabbitClient *rabbitmq.RabbitMQClient
	if cfg.RabbitMQURL != "" {
		var err error
		rabbitClient, err = rabbitmq.NewRabbitMQClient(cfg, rabbitIn, rabbitEvents)
		if err != nil {
			log.Printf("Warning: Failed to connect to RabbitMQ: %v", err)
		} else {
			defer rabbitClient.Close()
		}
	}

	// Hub needs NotificationService to send push when user offline
	hub := websocket.NewHub(messageUsecase, roomUsecase, onlineRepo, rabbitClient, rabbitIn, rabbitEvents, notificationService)

	// Create SocketController
	socketController := websocket.NewSocketController(hub, messageUsecase)

	go hub.Run()

	// Initialize FriendUsecase (Requires Hub/NotificationService for notifications)
	// We passed Hub to FriendUsecase before because Hub implemented NotificationService (via SendNotification method stub)
	// But now we have a real NotificationService.
	// FriendUsecase expects `domain.NotificationService`.
	// Hub *also* has SendNotification method.
	// Let's use the real notificationService for FriendUsecase if we want Push.
	// OR use Hub if we want WebSocket notification + Push fallback?
	// The previous implementation injected `hub` into `FriendUsecase`.
	// Hub's `SendNotification` was just sending WS.
	// We should update Hub to use `notificationService` internally for fallback, OR update FriendUsecase to use `notificationService` directly.
	// If we use `notificationService` directly in FriendUsecase, we get Push but maybe not WS realtime if app is open?
	// `OneSignalService` only does Push.
	// We want BOTH: WS if online, Push if offline.
	// Hub is the best place for this logic.
	// So Hub should wrap `notificationService`.
	// And FriendUsecase should keep using Hub (as NotificationService).

	friendUsecase := usecase.NewFriendUsecase(friendRepo, userRepo, hub, timeout)

	// Register Handlers
	delivery.NewUserHandler(r, userUsecase, cfg.JWTSecret, hub)
	delivery.NewMessageHandler(r, messageUsecase, hub, authMiddleware)
	delivery.NewRoomHandler(r, roomUsecase, userUsecase, authMiddleware)
	delivery.NewMediaHandler(r, authMiddleware)
	delivery.NewOnlineHandler(r, onlineRepo, authMiddleware)
	delivery.NewFriendHandler(r, friendUsecase, cfg.JWTSecret)
	delivery.NewDeviceHandler(r, deviceUsecase, authMiddleware)
	delivery.NewChatSettingHandler(r, chatSettingUsecase, authMiddleware) // 👉 新增設定的 Handler

	// Register WebSocket Route
	r.GET("/ws", func(c *gin.Context) {
		websocket.ServeWs(hub, c, cfg.JWTSecret, socketController)
	})

	// Register Metrics Endpoint
	r.GET("/metrics", func(c *gin.Context) {
		// Simple metrics
		c.JSON(http.StatusOK, gin.H{
			"active_connections": hub.GetActiveConnectionCount(),
			"timestamp":          time.Now(),
		})
	})

	// 7. Start Server with Graceful Shutdown
	srv := &http.Server{
		Addr:    ":8080",
		Handler: r,
	}

	// Initializing the server in a goroutine so that
	// it won't block the graceful shutdown handling below
	go func() {
		log.Printf("Server is starting on port 8080 (Env: %s)...", cfg.AppEnv)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("listen: %s\n", err)
		}
	}()

	// Wait for interrupt signal to gracefully shutdown the server with
	// a timeout of 5 seconds.
	quit := make(chan os.Signal, 1)
	// kill (no param) default send syscall.SIGTERM
	// kill -2 is syscall.SIGINT
	// kill -9 is syscall.SIGKILL but can't be catch, so don't need add it
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("Shutting down server...")

	// The context is used to inform the server it has 5 seconds to finish
	// the request it is currently handling
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		log.Fatal("Server forced to shutdown: ", err)
	}

	log.Println("Server exiting")
}
