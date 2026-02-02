package websockets

import (
	"context"
	// "encoding/json"
	"fmt"
	"log"
	"net/url"
	"time"

	"chatwme/backend/config"
	"chatwme/backend/database"
	"chatwme/backend/models"
	"chatwme/backend/utils"

	socketio "github.com/googollee/go-socket.io"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
)

// AuthenticatedUser 用于储存从 token 解析出的使用者资讯
type AuthenticatedUser struct {
	ID       string
	Username string
}

// ChatMessagePayload 定义了从客户端接收到的聊天讯息结构
type ChatMessagePayload struct {
	Room    string `json:"room"`
	Content string `json:"content"`
	Type    string `json:"type"`
}

// NewSocketIOServer 建立并配置一个新的 Socket.IO 伺服器
func NewSocketIOServer() *socketio.Server {
	server := socketio.NewServer(nil)

	// 在現有的事件處理中添加語音消息支持
	server.OnEvent("/", "voice_message", func(s socketio.Conn, payload map[string]interface{}) {
		user, ok := s.Context().(*AuthenticatedUser)
		if !ok || user == nil {
			log.Printf("Error: Could not get user from context for socket %s", s.ID())
			return
		}

		room, ok := payload["room"].(string)
		if !ok {
			log.Printf("Invalid room in voice message from %s", user.Username)
			return
		}

		// 廣播語音消息給房間內所有用戶
		voiceMessageData := map[string]interface{}{
			"id":          payload["id"],
			"sender_id":   user.ID,
			"sender_name": user.Username,
			"room":        room,
			"file_url":    payload["file_url"],
			"duration":    payload["duration"],
			"file_size":   payload["file_size"],
			"timestamp":   payload["timestamp"],
			"type":        "voice",
		}

		log.Printf("Broadcasting voice message from %s in room %s", user.Username, room)
		server.BroadcastToRoom("/", room, "voice_message", voiceMessageData)
	})

	// 当有新的客户端连线时触发 - 进行 Token 验证
	server.OnConnect("/", func(s socketio.Conn) error {
		queryValues, err := url.ParseQuery(s.URL().RawQuery)
		if err != nil {
			log.Printf("Connection rejected: Could not parse query for socket %s. Error: %v", s.ID(), err)
			return fmt.Errorf("authentication error: invalid query parameters")
		}
		token := queryValues.Get("token")

		if token == "" {
			log.Printf("Connection rejected: No token provided for socket %s", s.ID())
			return fmt.Errorf("authentication error: no token")
		}

		claims, err := utils.VerifyJWT(token)
		if err != nil {
			log.Printf("Connection rejected: Invalid token for socket %s. Error: %v", s.ID(), err)
			return fmt.Errorf("authentication error: invalid token")
		}

		user := &AuthenticatedUser{
			ID:       claims.UserID,
			Username: claims.Username,
		}
		s.SetContext(user)

		log.Printf("Socket connected and authenticated: UserID=%s, Username=%s, SocketID=%s", user.ID, user.Username, s.ID())
		return nil
	})

	// 处理自定义的 "join_room" 事件
	server.OnEvent("/", "join_room", func(s socketio.Conn, room string) {
		user, ok := s.Context().(*AuthenticatedUser)
		if !ok || user == nil {
			log.Printf("Error: Could not get user from context for socket %s", s.ID())
			return
		}

		s.Join(room)
		log.Printf("User %s (Socket %s) joined room: %s", user.Username, s.ID(), room)
	})

	// 处理自定义的 "leave_room" 事件
	server.OnEvent("/", "leave_room", func(s socketio.Conn, room string) {
		user, ok := s.Context().(*AuthenticatedUser)
		if !ok || user == nil {
			log.Printf("Error: Could not get user from context for socket %s", s.ID())
			return
		}

		s.Leave(room)
		log.Printf("User %s (Socket %s) left room: %s", user.Username, s.ID(), room)
	})

	// [關鍵修正] 處理心跳檢測
	server.OnEvent("/", "ping", func(s socketio.Conn) {
		user, ok := s.Context().(*AuthenticatedUser)
		userInfo := "unknown"
		if ok && user != nil {
			userInfo = user.Username
		}
		log.Printf("Received ping from %s (Socket %s)", userInfo, s.ID())
		s.Emit("pong")
	})

	// 处理自定义的 "chat_message" 事件
	server.OnEvent("/", "chat_message", func(s socketio.Conn, payload ChatMessagePayload) {
		user, ok := s.Context().(*AuthenticatedUser)
		if !ok || user == nil {
			log.Printf("Error: Could not get user from context for socket %s", s.ID())
			return
		}

		log.Printf("Message from %s (UserID: %s) in room %s: %s", user.Username, user.ID, payload.Room, payload.Content)

		// 載入設定以取得加密金鑰
		cfg := config.LoadConfig()
		encryptionKey := []byte(cfg.EncryptionSecret)

		// 將訊息内容加密
		encryptedContent, err := utils.Encrypt(payload.Content, encryptionKey)
		if err != nil {
			log.Printf("Error encrypting message from UserID %s: %v", user.ID, err)
			return
		}

		// 設置消息類型預設值
		messageType := payload.Type
		if messageType == "" {
			messageType = "text"
		}

		// 1. 建立要儲存到資料庫的訊息物件 (使用加密後的内容)
		messageToSave := models.Message{
			ID:         primitive.NewObjectID(),
			SenderID:   user.ID,
			SenderName: user.Username, // 添加發送者用戶名
			Room:       payload.Room,
			Content:    encryptedContent, // 儲存加密後的内容
			Timestamp:  time.Now(),
			Type:       messageType,
		}

		// 2. 存入 MongoDB
		collection := database.GetCollection("messages", cfg.MongoDbName)
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()

		_, err = collection.InsertOne(ctx, messageToSave)
		if err != nil {
			log.Printf("Failed to save message to database: %v", err)
			return
		}

		log.Printf("Message saved to database with ID: %s", messageToSave.ID.Hex())

		// 3. [關鍵修正] 建立要廣播給客戶端的訊息物件，確保格式與前端模型一致
		messageToBroadcast := map[string]interface{}{
			"id":          messageToSave.ID.Hex(),
			"sender_id":   user.ID,
			"sender_name": user.Username, // 確保包含發送者用戶名
			"room":        payload.Room,
			"content":     payload.Content, // 廣播原始内容
			"timestamp":   messageToSave.Timestamp.Format(time.RFC3339),
			"type":        messageType,
		}

		// 4. [關鍵修正] 廣播給房間內所有用戶，包括發送者自己
		log.Printf("Broadcasting message to room %s from %s: %s", payload.Room, user.Username, payload.Content)
		server.BroadcastToRoom("/", payload.Room, "chat_message", messageToBroadcast)

		// 5. 同步更新聊天室資訊
		go func() {
			roomCollection := database.GetCollection("chat_rooms", cfg.MongoDbName)
			roomObjectID, err := primitive.ObjectIDFromHex(payload.Room)
			if err != nil {
				log.Printf("Invalid Room ObjectID for update: %s, Error: %v", payload.Room, err)
				return
			}

			updateCtx, updateCancel := context.WithTimeout(context.Background(), 10*time.Second)
			defer updateCancel()

			// 更新聊天室的 last_message, last_message_time
			roomUpdate := bson.M{
				"$set": bson.M{
					"last_message":      payload.Content, // 使用原始内容
					"last_message_time": messageToSave.Timestamp,
					"updated_at":        time.Now(),
				},
				// 注意：這裡不增加 unread_count，因為會在前端根據發送者來決定
			}

			_, err = roomCollection.UpdateOne(updateCtx, bson.M{"_id": roomObjectID}, roomUpdate)
			if err != nil {
				log.Printf("Failed to update room last message: %v", err)
			} else {
				log.Printf("Room %s last message updated successfully", payload.Room)
			}
		}()
	})

	// 处理打字状態
	server.OnEvent("/", "typing", func(s socketio.Conn, data map[string]interface{}) {
		user, ok := s.Context().(*AuthenticatedUser)
		if !ok || user == nil {
			log.Printf("Error: Could not get user from context for socket %s", s.ID())
			return
		}

		room, ok := data["room"].(string)
		if !ok {
			log.Printf("Invalid room in typing event from %s", user.Username)
			return
		}

		isTyping, ok := data["is_typing"].(bool)
		if !ok {
			log.Printf("Invalid is_typing in typing event from %s", user.Username)
			return
		}

		// 廣播打字狀態給房間内的其他用戶（不包括發送者自己）
		typingData := map[string]interface{}{
			"user_id":   user.ID,
			"username":  user.Username,
			"room":      room,
			"is_typing": isTyping,
		}

		log.Printf("Broadcasting typing status from %s in room %s: %v", user.Username, room, isTyping)
		server.BroadcastToRoom("/", room, "typing", typingData)
	})

	// 當客戶端發生錯誤時觸發
	server.OnError("/", func(s socketio.Conn, e error) {
		// ✅ 關鍵修正：在所有操作之前，先檢查連線物件 s 是否為 nil
		if s == nil {
			log.Printf("Socket error with a nil connection: %v", e)
			return
		}

		user, ok := s.Context().(*AuthenticatedUser)
		userInfo := "unknown"
		if ok && user != nil {
			userInfo = user.Username
		}
		log.Printf("Socket error for %s (Socket %s): %v", userInfo, s.ID(), e)
	})

	// 當客戶端斷線時觸發
	server.OnDisconnect("/", func(s socketio.Conn, reason string) {
		// 這裡使用了安全的 "comma-ok" 型別斷言
		user, ok := s.Context().(*AuthenticatedUser)

		// 只有在 ok 為 true 且 user 不為 nil 的情況下，才會執行這個區塊
		if ok && user != nil {
			log.Printf("User %s disconnected (SocketID: %s): %s", user.Username, s.ID(), reason)
		} else {
			// 如果使用者未經驗證 (例如 Token 過期被拒絕)，則會安全地執行這個區塊
			log.Printf("Unauthenticated socket disconnected (SocketID: %s): %s", s.ID(), reason)
		}
	})

	return server
}
