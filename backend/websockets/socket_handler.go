package websockets

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/url"
	"time"

	"chatwme/backend/services"
	"chatwme/backend/utils"

	socketio "github.com/googollee/go-socket.io"
	"go.mongodb.org/mongo-driver/bson/primitive"
)

// AuthenticatedUser 用于储存从 token 解析出的使用者资讯
type AuthenticatedUser struct {
	ID       string
	Username string
}

// ChatMessagePayload 定义了从客户端接收到的聊天讯息结构
type ChatMessagePayload struct {
	ID        string `json:"id"` // 🔥 新增：客戶端生成的臨時 ID
	Room      string `json:"room"`
	Content   string `json:"content"`
	Type      string `json:"type"`
	Timestamp string `json:"timestamp"`
}

func toInt(value interface{}) int {
	switch v := value.(type) {
	case int:
		return v
	case int32:
		return int(v)
	case int64:
		return int(v)
	case float32:
		return int(v)
	case float64:
		return int(v)
	case json.Number:
		if i, err := v.Int64(); err == nil {
			return int(i)
		}
	}
	return 0
}

func toInt64(value interface{}) int64 {
	switch v := value.(type) {
	case int:
		return int64(v)
	case int32:
		return int64(v)
	case int64:
		return v
	case float32:
		return int64(v)
	case float64:
		return int64(v)
	case json.Number:
		if i, err := v.Int64(); err == nil {
			return i
		}
	}
	return 0
}

// NewSocketIOServer 建立并配置一个新的 Socket.IO 伺服器
func NewSocketIOServer(chatService *services.ChatService, redisOptions *socketio.RedisAdapterOptions) *socketio.Server {
	server := socketio.NewServer(nil)
	if redisOptions != nil {
		if _, err := server.Adapter(redisOptions); err != nil {
			log.Fatalf("Failed to set Redis adapter: %v", err)
		}
	}

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

		tempID, _ := payload["id"].(string)
		fileURL, ok := payload["file_url"].(string)
		if !ok || fileURL == "" {
			log.Printf("Invalid file_url in voice message from %s", user.Username)
			return
		}

		roomObjectID, err := primitive.ObjectIDFromHex(room)
		if err != nil {
			log.Printf("Invalid room ID in voice message: %s", room)
			return
		}

		authCtx, authCancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer authCancel()

		isMember, err := chatService.IsUserInRoom(authCtx, roomObjectID, user.ID)
		if err != nil || !isMember {
			log.Printf("Unauthorized voice message attempt by %s in room %s", user.ID, room)
			return
		}

		duration := toInt(payload["duration"])
		fileSize := toInt64(payload["file_size"])
		voiceInfo := map[string]interface{}{
			"file_url":  fileURL,
			"duration":  duration,
			"file_size": fileSize,
			"type":      "voice",
		}

		voiceContentBytes, err := json.Marshal(voiceInfo)
		if err != nil {
			log.Printf("Failed to marshal voice message content: %v", err)
			return
		}

		messageCtx, messageCancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer messageCancel()

		// 🔥 修正：使用 SaveMessage 讓後端生成 ID，而不是使用前端的臨時 ID
		savedMessage, err := chatService.SaveMessage(
			messageCtx,
			user.ID,
			user.Username,
			room,
			string(voiceContentBytes),
			"voice",
			fileURL,
			duration,
			fileSize,
		)
		if err != nil {
			log.Printf("Failed to save voice message: %v", err)
			return
		}

		broadcastTimestamp, _ := payload["timestamp"].(string)
		if broadcastTimestamp == "" {
			broadcastTimestamp = savedMessage.Timestamp.Format(time.RFC3339)
		}

		// 廣播語音消息給房間內所有用戶
		voiceMessageData := map[string]interface{}{
			"id":          savedMessage.ID.Hex(), // 後端生成的真實 ID
			"temp_id":     tempID,                // 🔥 返回前端的臨時 ID
			"sender_id":   user.ID,
			"sender_name": user.Username,
			"room":        room,
			"file_url":    fileURL,
			"duration":    duration,
			"file_size":   fileSize,
			"timestamp":   broadcastTimestamp,
			"type":        "voice",
		}

		log.Printf("Broadcasting voice message from %s in room %s", user.Username, room)
		server.BroadcastToRoom("/", room, "voice_message", voiceMessageData)
		
		go func(ts time.Time) {
			updateCtx, updateCancel := context.WithTimeout(context.Background(), 10*time.Second)
			defer updateCancel()
			if err := chatService.UpdateRoomLastMessage(updateCtx, roomObjectID, "[语音消息]", ts); err != nil {
				log.Printf("Failed to update room last message: %v", err)
			}
		}(savedMessage.Timestamp)
	})

	// 🔥 新增：支持图片消息广播
	server.OnEvent("/", "image_message", func(s socketio.Conn, payload map[string]interface{}) {
		user, ok := s.Context().(*AuthenticatedUser)
		if !ok || user == nil {
			log.Printf("Error: Could not get user from context for socket %s", s.ID())
			return
		}

		room, ok := payload["room"].(string)
		if !ok {
			log.Printf("Invalid room in image message from %s", user.Username)
			return
		}

		tempID, _ := payload["id"].(string)
		fileURL, ok := payload["file_url"].(string)
		if !ok || fileURL == "" {
			log.Printf("Invalid file_url in image message from %s", user.Username)
			return
		}

		roomObjectID, err := primitive.ObjectIDFromHex(room)
		if err != nil {
			log.Printf("Invalid room ID in image message: %s", room)
			return
		}

		authCtx, authCancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer authCancel()

		isMember, err := chatService.IsUserInRoom(authCtx, roomObjectID, user.ID)
		if err != nil || !isMember {
			log.Printf("Unauthorized image message attempt by %s in room %s", user.ID, room)
			return
		}

		imageInfo := map[string]interface{}{
			"file_url": fileURL,
			"type":     "image",
		}

		imageContentBytes, err := json.Marshal(imageInfo)
		if err != nil {
			log.Printf("Failed to marshal image message content: %v", err)
			return
		}

		messageCtx, messageCancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer messageCancel()

		// 🔥 修正：使用 SaveMessage
		savedMessage, err := chatService.SaveMessage(
			messageCtx,
			user.ID,
			user.Username,
			room,
			string(imageContentBytes),
			"image",
			fileURL,
			0,
			0,
		)
		if err != nil {
			log.Printf("Failed to save image message: %v", err)
			return
		}

		broadcastTimestamp, _ := payload["timestamp"].(string)
		if broadcastTimestamp == "" {
			broadcastTimestamp = savedMessage.Timestamp.Format(time.RFC3339)
		}

		// 广播图片消息给房间内所有用户
		imageMessageData := map[string]interface{}{
			"id":          savedMessage.ID.Hex(),
			"temp_id":     tempID, // 🔥 返回 temp_id
			"sender_id":   user.ID,
			"sender_name": user.Username,
			"room":        room,
			"file_url":    fileURL,
			"timestamp":   broadcastTimestamp,
			"type":        "image",
		}

		log.Printf("Broadcasting image message from %s in room %s", user.Username, room)
		server.BroadcastToRoom("/", room, "image_message", imageMessageData)
		
		go func(ts time.Time) {
			updateCtx, updateCancel := context.WithTimeout(context.Background(), 10*time.Second)
			defer updateCancel()
			if err := chatService.UpdateRoomLastMessage(updateCtx, roomObjectID, "[图片]", ts); err != nil {
				log.Printf("Failed to update room last message: %v", err)
			}
		}(savedMessage.Timestamp)
	})

	// 🔥 新增：支持视频消息广播
	server.OnEvent("/", "video_message", func(s socketio.Conn, payload map[string]interface{}) {
		user, ok := s.Context().(*AuthenticatedUser)
		if !ok || user == nil {
			log.Printf("Error: Could not get user from context for socket %s", s.ID())
			return
		}

		room, ok := payload["room"].(string)
		if !ok {
			log.Printf("Invalid room in video message from %s", user.Username)
			return
		}

		messageID, _ := payload["id"].(string)
		fileURL, ok := payload["file_url"].(string)
		if !ok || fileURL == "" {
			log.Printf("Invalid file_url in video message from %s", user.Username)
			return
		}

		roomObjectID, err := primitive.ObjectIDFromHex(room)
		if err != nil {
			log.Printf("Invalid room ID in video message: %s", room)
			return
		}

		authCtx, authCancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer authCancel()

		isMember, err := chatService.IsUserInRoom(authCtx, roomObjectID, user.ID)
		if err != nil || !isMember {
			log.Printf("Unauthorized video message attempt by %s in room %s", user.ID, room)
			return
		}

		duration := toInt(payload["duration"])
		fileSize := toInt64(payload["file_size"])
		videoInfo := map[string]interface{}{
			"file_url":  fileURL,
			"duration":  duration,
			"file_size": fileSize,
			"type":      "video",
		}

		videoContentBytes, err := json.Marshal(videoInfo)
		if err != nil {
			log.Printf("Failed to marshal video message content: %v", err)
			return
		}

		messageCtx, messageCancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer messageCancel()

		savedMessage, inserted, err := chatService.SaveMessageWithID(
			messageCtx,
			messageID,
			user.ID,
			user.Username,
			room,
			string(videoContentBytes),
			"video",
			fileURL,
			duration,
			fileSize,
		)
		if err != nil {
			log.Printf("Failed to save video message: %v", err)
			return
		}

		broadcastTimestamp, _ := payload["timestamp"].(string)
		if inserted {
			broadcastTimestamp = savedMessage.Timestamp.Format(time.RFC3339)
		} else if broadcastTimestamp == "" {
			broadcastTimestamp = time.Now().Format(time.RFC3339)
		}

		// 广播视频消息给房间内所有用户
		videoMessageData := map[string]interface{}{
			"id":          savedMessage.ID.Hex(),
			"sender_id":   user.ID,
			"sender_name": user.Username,
			"room":        room,
			"file_url":    fileURL,
			"timestamp":   broadcastTimestamp,
			"type":        "video",
		}

		log.Printf("Broadcasting video message from %s in room %s", user.Username, room)
		server.BroadcastToRoom("/", room, "video_message", videoMessageData)
		if inserted {
			go func(ts time.Time) {
				updateCtx, updateCancel := context.WithTimeout(context.Background(), 10*time.Second)
				defer updateCancel()
				if err := chatService.UpdateRoomLastMessage(updateCtx, roomObjectID, "[视频]", ts); err != nil {
					log.Printf("Failed to update room last message: %v", err)
				}
			}(savedMessage.Timestamp)
		}
	})

	// 🔥 新增：处理 "mark_read" 事件
	server.OnEvent("/", "mark_read", func(s socketio.Conn, payload map[string]interface{}) {
		user, ok := s.Context().(*AuthenticatedUser)
		if !ok || user == nil {
			log.Printf("Error: Could not get user from context for socket %s", s.ID())
			return
		}

		room, ok := payload["room"].(string)
		if !ok {
			log.Printf("Invalid room in mark_read from %s", user.Username)
			return
		}

		// 更新数据库中的消息状态
		// 注意：这里需要访问数据库，我们假设 chatService 有相应的方法，或者直接在這裡操作
		// 为了简单起见，我们直接在这里调用 chatService 的方法 (需要新增)
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()

		roomObjectID, err := primitive.ObjectIDFromHex(room)
		if err != nil {
			log.Printf("Invalid room ID: %s", room)
			return
		}

		if err := chatService.MarkMessagesAsRead(ctx, roomObjectID, user.ID); err != nil {
			log.Printf("Failed to mark messages as read: %v", err)
			return
		}

		// 广播 "message_read" 事件给房间内所有用户
		readData := map[string]interface{}{
			"room":      room,
			"user_id":   user.ID,
			"timestamp": time.Now().Format(time.RFC3339),
		}

		log.Printf("User %s marked messages as read in room %s", user.Username, room)
		server.BroadcastToRoom("/", room, "message_read", readData)
	})

	// 🔥 新增：处理 "typing_start" 事件
	server.OnEvent("/", "typing_start", func(s socketio.Conn, payload map[string]interface{}) {
		user, ok := s.Context().(*AuthenticatedUser)
		if !ok || user == nil {
			return
		}

		room, ok := payload["room"].(string)
		if !ok {
			return
		}

		typingData := map[string]interface{}{
			"room":        room,
			"sender_id":   user.ID,
			"sender_name": user.Username,
			"is_typing":   true,
		}

		// 广播给房间内的其他人（除了自己）
		// socket.io-go 的 BroadcastToRoom 默认会发给所有人包括自己吗？通常是的。
		// 但在这里我们希望接收端过滤掉自己。或者我们可以尝试用 s.BroadcastTo 排除自己。
		// server.BroadcastToRoom 确实是广播给房间里的所有 socket。
		// 客户端需要自己过滤 sender_id == current_user_id。
		server.BroadcastToRoom("/", room, "typing_start", typingData)
	})

	// 🔥 新增：处理 "typing_end" 事件
	server.OnEvent("/", "typing_end", func(s socketio.Conn, payload map[string]interface{}) {
		user, ok := s.Context().(*AuthenticatedUser)
		if !ok || user == nil {
			return
		}

		room, ok := payload["room"].(string)
		if !ok {
			return
		}

		typingData := map[string]interface{}{
			"room":        room,
			"sender_id":   user.ID,
			"sender_name": user.Username,
			"is_typing":   false,
		}

		server.BroadcastToRoom("/", room, "typing_end", typingData)
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
	server.OnEvent("/", "chat_message", func(s socketio.Conn, payload ChatMessagePayload, ack func(map[string]interface{})) {
		respondError := func(message string) {
			if ack != nil {
				ack(map[string]interface{}{
					"ok":    false,
					"error": message,
				})
			}
		}
		respondSuccess := func(messageID string, timestamp string) {
			if ack != nil {
				ack(map[string]interface{}{
					"ok":         true,
					"message_id": messageID,
					"timestamp":  timestamp,
					"temp_id":    payload.ID, // 🔥 新增：返回客戶端臨時 ID
				})
			}
		}

		user, ok := s.Context().(*AuthenticatedUser)
		if !ok || user == nil {
			log.Printf("Error: Could not get user from context for socket %s", s.ID())
			respondError("unauthorized")
			return
		}

		log.Printf("Message from %s (UserID: %s) in room %s: %s", user.Username, user.ID, payload.Room, payload.Content)

		// 0. [安全檢查] 速率限制
		rateCtx, rateCancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer rateCancel()
		allowed, err := chatService.CheckRateLimit(rateCtx, user.ID)
		if err != nil {
			log.Printf("Rate limit check failed for UserID %s: %v", user.ID, err)
			// Fail open or closed? Let's fail open but log it.
		} else if !allowed {
			log.Printf("Rate limit exceeded for UserID %s", user.ID)
			respondError("rate_limit_exceeded")
			return
		}

		roomObjectID, err := primitive.ObjectIDFromHex(payload.Room)
		if err != nil {
			log.Printf("Invalid Room ObjectID for message: %s, Error: %v", payload.Room, err)
			respondError("invalid_room")
			return
		}

		authCtx, authCancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer authCancel()

		isMember, err := chatService.IsUserInRoom(authCtx, roomObjectID, user.ID)
		if err != nil {
			log.Printf("Failed to validate room access for UserID %s in room %s: %v", user.ID, payload.Room, err)
			respondError("room_access_check_failed")
			return
		}
		if !isMember {
			log.Printf("Unauthorized message attempt by UserID %s in room %s", user.ID, payload.Room)
			respondError("not_in_room")
			return
		}

		participants, err := chatService.GetRoomParticipants(authCtx, roomObjectID)
		if err != nil {
			log.Printf("Failed to get room participants for block check: %v", err)
			respondError("internal_error")
			return
		}

		blockerIDs := make([]string, 0, len(participants))
		for _, participantID := range participants {
			if participantID != user.ID {
				blockerIDs = append(blockerIDs, participantID)
			}
		}

		if len(blockerIDs) > 0 {
			isBlocked, err := chatService.IsUserBlockedByAny(authCtx, blockerIDs, user.ID)
			if err != nil {
				log.Printf("Error checking block status: %v", err)
			} else if isBlocked {
				log.Printf("Message rejected: User %s is blocked by a participant", user.ID)
				respondError("blocked")
				return
			}
		}

		// 設置消息類型預設值
		messageType := payload.Type
		if messageType == "" {
			messageType = "text"
		}

		messageCtx, messageCancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer messageCancel()

		messageToSave, err := chatService.SaveMessage(messageCtx, user.ID, user.Username, payload.Room, payload.Content, messageType, "", 0, 0)
		if err != nil {
			log.Printf("Failed to save message to database: %v", err)
			respondError("message_save_failed")
			return
		}

		log.Printf("Message saved to database with ID: %s", messageToSave.ID.Hex())
		respondSuccess(messageToSave.ID.Hex(), messageToSave.Timestamp.Format(time.RFC3339))

		// 3. [關鍵修正] 建立要廣播給客戶端的訊息物件，確保格式與前端模型一致
		messageToBroadcast := map[string]interface{}{
			"id":          messageToSave.ID.Hex(),
			"temp_id":     payload.ID, // 🔥 新增：廣播臨時 ID
			"sender_id":   user.ID,
			"sender_name": user.Username, // 確保包含發送者用戶名
			"room":        payload.Room,
			"content":     payload.Content, // 廣播原始内容
			"timestamp":   messageToSave.Timestamp.Format(time.RFC3339),
			"type":        messageType,
			"read_by":     []string{}, // 🔥 新增：初始已读列表
		}

		// 4. [關鍵修正] 廣播給房間內所有用戶，包括發送者自己
		log.Printf("Broadcasting message to room %s from %s: %s", payload.Room, user.Username, payload.Content)
		server.BroadcastToRoom("/", payload.Room, "chat_message", messageToBroadcast)

		// 5. 同步更新聊天室資訊
		go func() {
			updateCtx, updateCancel := context.WithTimeout(context.Background(), 10*time.Second)
			defer updateCancel()

			if err := chatService.UpdateRoomLastMessage(updateCtx, roomObjectID, payload.Content, messageToSave.Timestamp); err != nil {
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
