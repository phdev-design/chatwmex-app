package config

import (
	"log"
	"os"
	"strings"

	"github.com/spf13/viper"
)

type Config struct {
	AppEnv          string `mapstructure:"APP_ENV"`
	MongoURI        string `mapstructure:"MONGO_URI"`
	MongoDBName     string `mapstructure:"MONGO_DB_NAME"`
	RedisAddr       string `mapstructure:"REDIS_ADDR"`
	RedisPassword   string `mapstructure:"REDIS_PASSWORD"`
	RabbitMQURL     string `mapstructure:"RABBITMQ_URL"`
	EncryptionKey   string `mapstructure:"ENCRYPTION_KEY"`
	JWTSecret       string `mapstructure:"JWT_SECRET"`
	OneSignalAppID  string `mapstructure:"ONESIGNAL_APP_ID"`
	OneSignalAPIKey string `mapstructure:"ONESIGNAL_API_KEY"`
	StorageBaseURL  string `mapstructure:"STORAGE_BASE_URL"`
}

func LoadConfig() (*Config, error) {
	v := viper.New()

	// 1. Determine environment (dev or release)
	// Priority: MODE env var > APP_ENV env var > default "dev"
	env := os.Getenv("MODE")
	if env == "" {
		env = os.Getenv("APP_ENV")
	}
	if env == "" {
		env = "dev"
	}

	// Normalize to lowercase
	env = strings.ToLower(env)

	// 2. Set config file name based on environment
	v.SetConfigName(".env." + env) // e.g., .env.dev or .env.release
	v.SetConfigType("env")

	// 3. Add search paths
	v.AddConfigPath("configs")       // Look in configs/ relative to binary execution
	v.AddConfigPath("./configs")     // Look in ./configs
	v.AddConfigPath("../configs")    // Look in parent/configs
	v.AddConfigPath("../../configs") // Look in grandparent/configs

	// 4. Read from Environment Variables (override config file)
	v.AutomaticEnv()

	// --- 新增這段：明確綁定環境變數 ---
	// 確保即使找不到 .env 檔案，也能從 Docker 的 environment 中讀取設定
	v.BindEnv("APP_ENV")
	v.BindEnv("MONGO_URI")
	v.BindEnv("MONGO_DB_NAME")
	v.BindEnv("REDIS_ADDR")
	v.BindEnv("REDIS_PASSWORD")
	v.BindEnv("RABBITMQ_URL")
	v.BindEnv("ENCRYPTION_KEY")
	v.BindEnv("JWT_SECRET")
	v.BindEnv("ONESIGNAL_APP_ID")
	v.BindEnv("ONESIGNAL_API_KEY")
	v.BindEnv("STORAGE_BASE_URL")
	// ------------------------------------

	if err := v.ReadInConfig(); err != nil {
		log.Printf("Warning: Config file .env.%s not found or unreadable: %v", env, err)
	} else {
		log.Printf("Loaded config from: %s", v.ConfigFileUsed())
	}

	var cfg Config
	if err := v.Unmarshal(&cfg); err != nil {
		return nil, err
	}

	// Ensure AppEnv is set correctly in struct even if not in file
	if cfg.AppEnv == "" {
		cfg.AppEnv = env
	}

	return &cfg, nil
}
