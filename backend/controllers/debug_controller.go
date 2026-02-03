package controllers

import (
	"context"
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"time"

	// "log"

	"chatwme/backend/config"
	"chatwme/backend/models"
	"chatwme/backend/utils"

	"github.com/gorilla/mux"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
)

// DebugSystemInfo 系统信息调试端点
func DebugSystemInfo(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	cfg := config.LoadConfig()

	uploadPath := os.Getenv("UPLOAD_PATH")
	if uploadPath == "" {
		uploadPath = "./uploads"
	}

	storageBaseURL := os.Getenv("STORAGE_BASE_URL")
	if storageBaseURL == "" {
		if os.Getenv("USE_CLOUDFLARE") == "true" || os.Getenv("ENVIRONMENT") == "production" {
			storageBaseURL = "https://api-chatwmex.phdev.uk/uploads"
		} else {
			storageBaseURL = "http://192.168.100.110:8080/uploads"
		}
	}

	absUploadPath, _ := filepath.Abs(uploadPath)

	// 检查上传目录是否存在
	_, uploadDirErr := os.Stat(absUploadPath)

	debugInfo := map[string]interface{}{
		"server_version":        cfg.AppVersion,
		"server_port":           cfg.ServerPort,
		"upload_path":           uploadPath,
		"abs_upload_path":       absUploadPath,
		"upload_dir_exists":     uploadDirErr == nil,
		"storage_base_url":      storageBaseURL,
		"mongo_db_name":         cfg.MongoDbName,
		"encryption_key_length": len(cfg.EncryptionSecret),
		"environment":           getEnvironmentInfo(),
		"timestamp":             time.Now().Format(time.RFC3339),
	}

	if uploadDirErr != nil {
		debugInfo["upload_dir_error"] = uploadDirErr.Error()
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(debugInfo)
}

// getEnvironmentInfo 获取环境信息
func getEnvironmentInfo() map[string]interface{} {
	return map[string]interface{}{
		"ENVIRONMENT":      os.Getenv("ENVIRONMENT"),
		"USE_CLOUDFLARE":   os.Getenv("USE_CLOUDFLARE"),
		"SERVER_PORT":      os.Getenv("SERVER_PORT"),
		"UPLOAD_PATH":      os.Getenv("UPLOAD_PATH"),
		"STORAGE_BASE_URL": os.Getenv("STORAGE_BASE_URL"),
	}
}

// DebugVoiceMessageDetailed 详细的语音消息调试端点
func DebugVoiceMessageDetailed(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	params := mux.Vars(r)
	messageID := params["messageId"]

	if messageID == "" {
		http.Error(w, `{"error": "Message ID is required"}`, http.StatusBadRequest)
		return
	}

	cfg := config.LoadConfig()
	store, ok := getStore(r)
	if !ok {
		http.Error(w, `{"error": "資料庫尚未初始化"}`, http.StatusInternalServerError)
		return
	}
	messageCollection := store.Collection("messages")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	messageObjectID, err := primitive.ObjectIDFromHex(messageID)
	if err != nil {
		http.Error(w, `{"error": "Invalid message ID"}`, http.StatusBadRequest)
		return
	}

	var message models.Message
	err = messageCollection.FindOne(ctx, bson.M{"_id": messageObjectID}).Decode(&message)

	debugInfo := map[string]interface{}{
		"message_id":     messageID,
		"message_exists": err == nil,
		"query_error":    nil,
	}

	if err != nil {
		debugInfo["query_error"] = err.Error()
	} else {
		// 消息存在，获取详细信息
		debugInfo["raw_message"] = map[string]interface{}{
			"id":             message.ID.Hex(),
			"sender_id":      message.SenderID,
			"sender_name":    message.SenderName,
			"room":           message.Room,
			"type":           message.Type,
			"timestamp":      message.Timestamp.Format(time.RFC3339),
			"content_length": len(message.Content),
		}

		// 尝试解密内容
		encryptionKey := []byte(cfg.EncryptionSecret)
		decryptedContent, decryptErr := utils.Decrypt(message.Content, encryptionKey)

		debugInfo["decryption"] = map[string]interface{}{
			"success": decryptErr == nil,
			"error":   nil,
		}

		if decryptErr != nil {
			debugInfo["decryption"].(map[string]interface{})["error"] = decryptErr.Error()
		} else {
			debugInfo["decrypted_content"] = decryptedContent

			// 如果是语音消息，尝试解析JSON
			if message.Type == "voice" {
				var voiceInfo map[string]interface{}
				jsonErr := json.Unmarshal([]byte(decryptedContent), &voiceInfo)

				debugInfo["voice_parsing"] = map[string]interface{}{
					"success": jsonErr == nil,
					"error":   nil,
				}

				if jsonErr != nil {
					debugInfo["voice_parsing"].(map[string]interface{})["error"] = jsonErr.Error()
				} else {
					debugInfo["voice_info"] = voiceInfo

					// 检查文件是否实际存在
					if fileURL, ok := voiceInfo["file_url"].(string); ok {
						debugInfo["file_url"] = fileURL

						// 尝试从URL提取文件路径并检查文件是否存在
						if filePath := utils.ExtractFilePathFromURL(fileURL); filePath != "" {
							uploadPath := os.Getenv("UPLOAD_PATH")
							if uploadPath == "" {
								uploadPath = "./uploads"
							}

							fullPath := filepath.Join(uploadPath, filePath)
							_, fileErr := os.Stat(fullPath)

							debugInfo["file_check"] = map[string]interface{}{
								"extracted_path": filePath,
								"full_path":      fullPath,
								"exists":         fileErr == nil,
								"error":          nil,
							}

							if fileErr != nil {
								debugInfo["file_check"].(map[string]interface{})["error"] = fileErr.Error()
							}
						}
					}
				}
			}
		}
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(debugInfo)
}

// DebugListVoiceMessages 列出所有语音消息
func DebugListVoiceMessages(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	cfg := config.LoadConfig()
	store, ok := getStore(r)
	if !ok {
		http.Error(w, `{"error": "資料庫尚未初始化"}`, http.StatusInternalServerError)
		return
	}
	messageCollection := store.Collection("messages")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// 查找所有语音消息
	cursor, err := messageCollection.Find(ctx, bson.M{"type": "voice"})
	if err != nil {
		http.Error(w, `{"error": "Failed to query voice messages"}`, http.StatusInternalServerError)
		return
	}
	defer cursor.Close(ctx)

	var messages []models.Message
	if err = cursor.All(ctx, &messages); err != nil {
		http.Error(w, `{"error": "Failed to decode voice messages"}`, http.StatusInternalServerError)
		return
	}

	debugInfo := map[string]interface{}{
		"total_voice_messages": len(messages),
		"messages":             []map[string]interface{}{},
	}

	encryptionKey := []byte(cfg.EncryptionSecret)

	for _, msg := range messages {
		msgInfo := map[string]interface{}{
			"id":             msg.ID.Hex(),
			"sender_name":    msg.SenderName,
			"room":           msg.Room,
			"timestamp":      msg.Timestamp.Format(time.RFC3339),
			"content_length": len(msg.Content),
		}

		// 尝试解密和解析
		decryptedContent, decryptErr := utils.Decrypt(msg.Content, encryptionKey)
		if decryptErr == nil {
			var voiceInfo map[string]interface{}
			if jsonErr := json.Unmarshal([]byte(decryptedContent), &voiceInfo); jsonErr == nil {
				msgInfo["file_url"] = voiceInfo["file_url"]
				msgInfo["duration"] = voiceInfo["duration"]
				msgInfo["file_size"] = voiceInfo["file_size"]
			}
		}

		debugInfo["messages"] = append(debugInfo["messages"].([]map[string]interface{}), msgInfo)
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(debugInfo)
}
