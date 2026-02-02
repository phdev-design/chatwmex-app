package main

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"os"
	"strings"
	"time"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

// 配置结构
type Config struct {
	MongoURI         string
	MongoDbName      string
	EncryptionSecret string
	StorageBaseURL   string
}

// VoiceMessageLegacy 原始语音消息结构
type VoiceMessageLegacy struct {
	ID         primitive.ObjectID `bson:"_id,omitempty"`
	SenderID   string             `bson:"sender_id"`
	SenderName string             `bson:"sender_name"`
	Room       string             `bson:"room"`
	FilePath   string             `bson:"file_path"`
	Duration   int                `bson:"duration"`
	FileSize   int64              `bson:"file_size"`
	Timestamp  time.Time          `bson:"timestamp"`
	Type       string             `bson:"type"`
}

// Message 统一消息结构
type Message struct {
	ID         primitive.ObjectID `bson:"_id,omitempty"`
	SenderID   string             `bson:"sender_id"`
	SenderName string             `bson:"sender_name"`
	Room       string             `bson:"room"`
	Content    string             `bson:"content"`
	Timestamp  time.Time          `bson:"timestamp"`
	Type       string             `bson:"type"`
}

// 加载配置
func loadConfig() *Config {
	config := &Config{
		MongoURI:         getEnv("MONGO_URI", "mongodb://cph0325:pp325325@143.198.17.2:27017"),
		MongoDbName:      getEnv("MONGO_DB_NAME", "chatwme_db"),
		EncryptionSecret: getEnv("ENCRYPTION_SECRET", "you-32-character-secret-key-here"),
		StorageBaseURL:   getEnv("STORAGE_BASE_URL", "https://api-chatwmex.phdev.uk/uploads"),
	}

	// 验证必要的配置
	if len(config.EncryptionSecret) != 32 {
		log.Fatalf("ENCRYPTION_SECRET 必须是 32 个字符长度，当前长度: %d", len(config.EncryptionSecret))
	}

	return config
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

// AES-GCM 加密函数
func encrypt(plaintext string, key []byte) (string, error) {
	block, err := aes.NewCipher(key)
	if err != nil {
		return "", err
	}

	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}

	nonce := make([]byte, gcm.NonceSize())
	if _, err = io.ReadFull(rand.Reader, nonce); err != nil {
		return "", err
	}

	ciphertextBytes := gcm.Seal(nonce, nonce, []byte(plaintext), nil)
	return base64.StdEncoding.EncodeToString(ciphertextBytes), nil
}

// 获取公共URL
func getPublicURL(filePath, baseURL string) string {
	normalizedPath := strings.ReplaceAll(filePath, "\\", "/")
	return fmt.Sprintf("%s/%s", strings.TrimRight(baseURL, "/"), strings.TrimLeft(normalizedPath, "/"))
}

func main() {
	fmt.Println("=== 开始语音消息迁移 ===")

	// 1. 加载配置
	cfg := loadConfig()

	fmt.Printf("MongoDB URI: %s\n", cfg.MongoURI)
	fmt.Printf("Database: %s\n", cfg.MongoDbName)
	fmt.Printf("Storage Base URL: %s\n", cfg.StorageBaseURL)

	// 2. 连接 MongoDB
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	client, err := mongo.Connect(ctx, options.Client().ApplyURI(cfg.MongoURI))
	if err != nil {
		log.Fatalf("连接 MongoDB 失败: %v", err)
	}
	defer client.Disconnect(context.Background())

	// 测试连接
	if err := client.Ping(ctx, nil); err != nil {
		log.Fatalf("MongoDB ping 失败: %v", err)
	}

	fmt.Println("✓ MongoDB 连接成功")

	// 3. 获取集合
	db := client.Database(cfg.MongoDbName)
	voiceCollection := db.Collection("voice_messages")
	messageCollection := db.Collection("messages")

	// 4. 检查是否有语音消息需要迁移
	count, err := voiceCollection.CountDocuments(ctx, bson.M{})
	if err != nil {
		log.Fatalf("统计语音消息失败: %v", err)
	}

	if count == 0 {
		fmt.Println("没有找到需要迁移的语音消息")
		return
	}

	fmt.Printf("找到 %d 条语音消息需要迁移\n", count)

	// 5. 查找所有语音消息
	cursor, err := voiceCollection.Find(ctx, bson.M{})
	if err != nil {
		log.Fatalf("查询语音消息失败: %v", err)
	}
	defer cursor.Close(ctx)

	var (
		migratedCount = 0
		errorCount    = 0
		skippedCount  = 0
	)

	encryptionKey := []byte(cfg.EncryptionSecret)

	// 6. 遍历并迁移每条语音消息
	for cursor.Next(ctx) {
		var legacyVoiceMsg VoiceMessageLegacy
		if err := cursor.Decode(&legacyVoiceMsg); err != nil {
			log.Printf("解析语音消息失败: %v", err)
			errorCount++
			continue
		}

		// 检查是否已经迁移过
		existingCount, err := messageCollection.CountDocuments(ctx, bson.M{
			"_id":  legacyVoiceMsg.ID,
			"type": "voice",
		})
		if err != nil {
			log.Printf("检查现有消息失败: %v", err)
			errorCount++
			continue
		}

		if existingCount > 0 {
			fmt.Printf("语音消息 %s 已存在，跳过\n", legacyVoiceMsg.ID.Hex())
			skippedCount++
			continue
		}

		// 构建语音消息内容
		fileURL := legacyVoiceMsg.FilePath
		if !strings.HasPrefix(fileURL, "http") {
			fileURL = getPublicURL(legacyVoiceMsg.FilePath, cfg.StorageBaseURL)
		}

		voiceContent := map[string]interface{}{
			"file_url":  fileURL,
			"duration":  legacyVoiceMsg.Duration,
			"file_size": legacyVoiceMsg.FileSize,
			"type":      "voice",
		}

		// 转为JSON字符串
		contentBytes, err := json.Marshal(voiceContent)
		if err != nil {
			log.Printf("序列化语音内容失败: %v", err)
			errorCount++
			continue
		}

		// 加密内容
		encryptedContent, err := encrypt(string(contentBytes), encryptionKey)
		if err != nil {
			log.Printf("加密语音内容失败: %v", err)
			errorCount++
			continue
		}

		// 创建统一的消息文档
		newMessage := Message{
			ID:         legacyVoiceMsg.ID,
			SenderID:   legacyVoiceMsg.SenderID,
			SenderName: legacyVoiceMsg.SenderName,
			Room:       legacyVoiceMsg.Room,
			Content:    encryptedContent,
			Timestamp:  legacyVoiceMsg.Timestamp,
			Type:       "voice",
		}

		// 插入到 messages 集合
		_, err = messageCollection.InsertOne(ctx, newMessage)
		if err != nil {
			log.Printf("插入消息失败: %v", err)
			errorCount++
			continue
		}

		migratedCount++
		fmt.Printf("成功迁移语音消息 %s (%d/%d)\n",
			legacyVoiceMsg.ID.Hex(), migratedCount, int(count))
	}

	// 7. 打印迁移结果
	fmt.Println("\n=== 迁移完成 ===")
	fmt.Printf("成功迁移: %d 条\n", migratedCount)
	fmt.Printf("跳过(已存在): %d 条\n", skippedCount)
	fmt.Printf("错误: %d 条\n", errorCount)

	// 8. 验证迁移结果
	totalVoiceInMessages, err := messageCollection.CountDocuments(ctx, bson.M{"type": "voice"})
	if err != nil {
		log.Printf("验证失败: %v", err)
		return
	}

	fmt.Printf("\n=== 验证结果 ===\n")
	fmt.Printf("messages 集合中的语音消息数量: %d\n", totalVoiceInMessages)

	if totalVoiceInMessages >= count {
		fmt.Println("✓ 迁移验证成功！")
		fmt.Println("\n⚠️  建议：")
		fmt.Println("1. 验证前端功能正常后，可以删除 voice_messages 集合")
		fmt.Println("2. MongoDB 命令：db.voice_messages.drop()")
	} else {
		fmt.Println("⚠️  迁移可能不完整，请检查日志")
	}
}