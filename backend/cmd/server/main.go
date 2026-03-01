package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"chatwmex_backend/internal/config"
	delivery "chatwmex_backend/internal/delivery/http"
	"chatwmex_backend/internal/delivery/http/middleware"
	"chatwmex_backend/internal/delivery/websocket"
	"chatwmex_backend/internal/domain"
	"chatwmex_backend/internal/infrastructure"
	"chatwmex_backend/internal/infrastructure/rabbitmq"
	"chatwmex_backend/internal/repository/mongo_repo"
	"chatwmex_backend/internal/repository/redis_repo"
	"chatwmex_backend/internal/usecase"
	"chatwmex_backend/pkg/crypto"

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

	// Crypto Service
	// Ensure encryption key is valid (32 bytes for AES-256)
	if len(cfg.EncryptionKey) != 32 {
		log.Fatalf("Encryption key must be exactly 32 bytes (got %d)", len(cfg.EncryptionKey))
	}
	cryptor, err := crypto.NewAESCrypto(cfg.EncryptionKey)
	if err != nil {
		log.Fatalf("Failed to initialize crypto service: %v", err)
	}

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
	messageRepo := mongo_repo.NewMessageRepository(db, cryptor)
	roomRepo := mongo_repo.NewRoomRepository(db)
	onlineRepo := redis_repo.NewOnlineRepository(redisClient)

	// 4. Initialize Usecases
	// Set a default timeout for usecase operations
	timeout := 5 * time.Second
	userUsecase := usecase.NewUserUsecase(userRepo, timeout)
	messageUsecase := usecase.NewMessageUsecase(messageRepo, timeout)
	roomUsecase := usecase.NewRoomUsecase(roomRepo, timeout)

	// 5. Initialize HTTP Server
	if cfg.AppEnv == "release" {
		gin.SetMode(gin.ReleaseMode)
	}
	r := gin.Default()

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
	
	var rabbitClient *rabbitmq.RabbitMQClient
	if cfg.RabbitMQURL != "" {
		var err error
		rabbitClient, err = rabbitmq.NewRabbitMQClient(cfg, rabbitIn)
		if err != nil {
			log.Printf("Warning: Failed to connect to RabbitMQ: %v", err)
		} else {
			defer rabbitClient.Close()
		}
	}
	
	hub := websocket.NewHub(messageUsecase, roomUsecase, onlineRepo, rabbitClient, rabbitIn)
	
	// Create SocketController
	socketController := websocket.NewSocketController(hub, messageUsecase)
	
	go hub.Run()


	// Register Handlers
	delivery.NewUserHandler(r, userUsecase, cfg.JWTSecret)
	delivery.NewMessageHandler(r, messageUsecase, authMiddleware)
	delivery.NewRoomHandler(r, roomUsecase, authMiddleware)
	delivery.NewOnlineHandler(r, onlineRepo, authMiddleware)
	
	// Register WebSocket Route
	r.GET("/ws", func(c *gin.Context) {
		websocket.ServeWs(hub, c, cfg.JWTSecret, socketController)
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
