package config

import (
	"log"
	"os"

	"github.com/spf13/viper"
)

type Config struct {
	AppEnv        string `mapstructure:"APP_ENV"`
	MongoURI      string `mapstructure:"MONGO_URI"`
	MongoDBName   string `mapstructure:"MONGO_DB_NAME"`
	RedisAddr     string `mapstructure:"REDIS_ADDR"`
	RedisPassword string `mapstructure:"REDIS_PASSWORD"`
	RabbitMQURL   string `mapstructure:"RABBITMQ_URL"`
	EncryptionKey string `mapstructure:"ENCRYPTION_KEY"`
	JWTSecret     string `mapstructure:"JWT_SECRET"`
}

func LoadConfig() (*Config, error) {
	v := viper.New()

	// Default values
	v.SetDefault("APP_ENV", "dev")

	// 1. Read from Environment Variables
	v.AutomaticEnv()

	// 2. Determine which .env file to load
	// We check the environment variable APP_ENV directly first to decide the file
	appEnv := os.Getenv("APP_ENV")
	if appEnv == "" {
		appEnv = "dev"
	}

	// 3. Load config file
	v.SetConfigName(".env." + appEnv) // e.g., .env.dev or .env.release
	v.SetConfigType("env")
	v.AddConfigPath("configs")      // Look in configs/ directory
	v.AddConfigPath("./configs")    // Look in current directory/configs
	v.AddConfigPath("../configs")   // Look in parent/configs (for tests or cmd/server runs)
	v.AddConfigPath("../../configs") // Look in grandparent/configs

	if err := v.ReadInConfig(); err != nil {
		// It's acceptable if the config file is missing, provided all required variables are set in the environment.
		// However, for this setup, we'll log a warning.
		log.Printf("Warning: Config file .env.%s not found or unreadable: %v", appEnv, err)
	} else {
		log.Printf("Loaded config from: %s", v.ConfigFileUsed())
	}

	var cfg Config
	if err := v.Unmarshal(&cfg); err != nil {
		return nil, err
	}

	return &cfg, nil
}
