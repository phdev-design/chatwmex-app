package config

import (
	"log"
	"os"
	"sync"

	"github.com/joho/godotenv"
)

// 全局變數用於跟蹤日誌狀態
var (
	isDockerEnvLogged bool
	logMutex          sync.Mutex
)

// AppConfig 存放應用程式的所有設定
type AppConfig struct {
	AppVersion       string // 新增應用程式版本號
	Environment      string // 環境類型: production, development, testing
	ServerPort       string
	MongoURI         string
	MongoDbName      string
	JwtSecret        string   // 新增 JWT 密鑰
	EncryptionSecret string   // 新增用於訊息加密的密鑰
	StorageBaseURL   string   // 存儲基礎 URL
	UseCloudflare    bool     // 是否使用 Cloudflare
	AllowedOrigins   []string // 允許的來源
}

// LoadConfig 載入設定
func LoadConfig() AppConfig {
	// 檢查是否在 Docker 環境中
	if os.Getenv("DOCKER_ENV") == "true" || os.Getenv("CONTAINER") == "true" {
		// 在 Docker 環境中，直接使用環境變數，不嘗試加載 .env 文件
		// 只在第一次加載時輸出日誌（線程安全）
		logMutex.Lock()
		if !isDockerEnvLogged {
			log.Println("Docker environment detected, using environment variables")
			isDockerEnvLogged = true
		}
		logMutex.Unlock()
	} else {
		// 在本地開發環境中，嘗試從 .env 檔案載入環境變數
		err := godotenv.Load()
		if err != nil {
			log.Println("Warning: Could not find .env file, using environment variables")
		}
	}

	// 環境配置
	environment := os.Getenv("ENVIRONMENT")
	if environment == "" {
		// 自動檢測環境 - 本地執行時預設為開發環境
		if os.Getenv("DOCKER_ENV") == "true" || os.Getenv("CONTAINER") == "true" {
			// Docker 環境中根據 USE_CLOUDFLARE 判斷
			if os.Getenv("USE_CLOUDFLARE") == "true" {
				environment = "production"
			} else {
				environment = "development"
			}
		} else {
			// 本地執行時強制使用開發環境
			environment = "development"
		}
	}

	port := os.Getenv("SERVER_PORT")
	if port == "" {
		port = ":8080"
	}

	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://cph0325:pp325325@192.168.100.150:27017"
	}

	mongoDbName := os.Getenv("MONGO_DB_NAME")
	if mongoDbName == "" {
		// 根據環境自動選擇資料庫名稱
		if environment == "production" {
			mongoDbName = "chatwmex_db" // 生產環境使用正式資料庫
		} else {
			mongoDbName = "chat2mex_db_test" // 開發/測試環境使用測試資料庫
		}
	}

	jwtSecret := os.Getenv("JWT_SECRET")
	if jwtSecret == "" {
		log.Fatal("JWT_SECRET environment variable not set")
	}

	encryptionSecret := os.Getenv("ENCRYPTION_SECRET")
	if encryptionSecret == "" {
		log.Fatal("ENCRYPTION_SECRET environment variable not set")
	}
	if len(encryptionSecret) != 32 {
		log.Fatal("ENCRYPTION_SECRET must be 32 bytes long for AES-256")
	}

	// 存儲配置
	storageBaseURL := os.Getenv("STORAGE_BASE_URL")
	useCloudflare := os.Getenv("USE_CLOUDFLARE") == "true"

	if storageBaseURL == "" {
		if environment == "production" || useCloudflare {
			storageBaseURL = "https://api-chatwmex.phdev.uk/uploads"
		} else {
			// 開發環境，支援多種測試 URL
			testHost := os.Getenv("TEST_HOST")
			if testHost == "" {
				testHost = "192.168.100.111" // 預設本地測試（無端口）
			}
			storageBaseURL = "http://" + testHost + "/uploads"
		}
	}

	// CORS 配置
	var allowedOrigins []string
	if environment == "production" {
		allowedOrigins = []string{
			"https://chatwmex.phdev.uk",
			"https://www.chatwmex.phdev.uk",
		}
	} else {
		// 開發環境允許更多來源
		allowedOrigins = []string{
			"http://localhost:3000",
			"http://127.0.0.1:3000",
			"http://localhost:8080",
			"http://127.0.0.1:8080",
			"http://192.168.100.111:8080",
			"*", // 開發環境允許所有來源
		}
	}

	return AppConfig{
		AppVersion:       "1.0.30", // 設定應用程式版本
		Environment:      environment,
		ServerPort:       port,
		MongoURI:         mongoURI,
		MongoDbName:      mongoDbName,
		JwtSecret:        jwtSecret,
		EncryptionSecret: encryptionSecret,
		StorageBaseURL:   storageBaseURL,
		UseCloudflare:    useCloudflare,
		AllowedOrigins:   allowedOrigins,
	}
}
