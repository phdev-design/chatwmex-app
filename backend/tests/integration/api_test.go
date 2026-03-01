package integration

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"chatwme/backend/config"
	"chatwme/backend/database"
	"chatwme/backend/routes"
	"chatwme/backend/utils"

	"github.com/stretchr/testify/assert"
)

var (
	testRouter http.Handler
	authToken  string
	userID     string
)

func TestMain(m *testing.M) {
	// 1. Setup Environment
	os.Setenv("ENVIRONMENT", "testing")
	os.Setenv("MONGO_DB_NAME", "chatwmex_test_db")
	os.Setenv("JWT_SECRET", "test_secret_key_1234567890123456")
	os.Setenv("ENCRYPTION_SECRET", "12345678901234567890123456789012")

	// 2. Connect to Database
	cfg := config.LoadConfig()
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	store, err := database.NewMongoStore(ctx, cfg.MongoURI, cfg.MongoDbName)
	if err != nil {
		log.Fatalf("Failed to connect to test database: %v", err)
	}

	// Clean up database before tests
	// Use Collection to drop directly or add Drop method to Store interface if needed
	// For integration test, we can just access client via reflection or just use Collection("users").Drop(ctx) etc.
	// But MongoStore struct fields are private (client, dbName).
	// Let's modify database.go to expose Client or add a DropDatabase method.
	// OR: Since we can't easily modify production code just for tests in this thought process without multiple steps,
	// let's try to drop collections individually.
	store.Collection("users").Drop(ctx)
	store.Collection("chat_rooms").Drop(ctx)
	store.Collection("messages").Drop(ctx)
	store.Collection("blocked_users").Drop(ctx)

	// 3. Setup Router
	testRouter = routes.SetupRoutes(store)

	// 4. Create Test User & Token
	// The backend likely expects a valid MongoDB ObjectID for userID
	userID = "65a123456789012345678901" // Valid 24-char hex string
	token, _ := utils.GenerateJWT(userID, "testuser")
	authToken = "Bearer " + token

	// Run Tests
	code := m.Run()

	// Teardown
	store.Collection("users").Drop(ctx)
	store.Collection("chat_rooms").Drop(ctx)
	store.Collection("messages").Drop(ctx)
	store.Collection("blocked_users").Drop(ctx)
	store.Disconnect(ctx)

	os.Exit(code)
}

func executeRequest(req *http.Request) *httptest.ResponseRecorder {
	rr := httptest.NewRecorder()
	testRouter.ServeHTTP(rr, req)
	return rr
}

func TestHealthCheck(t *testing.T) {
	req, _ := http.NewRequest("GET", "/api/v1/health", nil)
	response := executeRequest(req)

	assert.Equal(t, http.StatusOK, response.Code)
	
	var body map[string]string
	json.Unmarshal(response.Body.Bytes(), &body)
	assert.Equal(t, "healthy", body["status"])
}

func TestGetChatRooms_Unauthorized(t *testing.T) {
	req, _ := http.NewRequest("GET", "/api/v1/rooms", nil)
	// No Auth Header
	response := executeRequest(req)

	assert.Equal(t, http.StatusUnauthorized, response.Code)
}

func TestGetChatRooms_Authorized(t *testing.T) {
	req, _ := http.NewRequest("GET", "/api/v1/rooms", nil)
	req.Header.Set("Authorization", authToken)
	response := executeRequest(req)

	assert.Equal(t, http.StatusOK, response.Code)
}

func TestCreateRoomAndSendMessage(t *testing.T) {
	// 1. Create Room
	roomPayload := map[string]interface{}{
		"name": "Test Room",
		"type": "group",
		"participants": []string{userID, "other_user_id"},
	}
	payloadBytes, _ := json.Marshal(roomPayload)
	req, _ := http.NewRequest("POST", "/api/v1/rooms", bytes.NewBuffer(payloadBytes))
	req.Header.Set("Authorization", authToken)
	req.Header.Set("Content-Type", "application/json")
	
	response := executeRequest(req)
	assert.Equal(t, http.StatusCreated, response.Code)

	var roomResp map[string]interface{}
	json.Unmarshal(response.Body.Bytes(), &roomResp)
	
	// Print response for debugging if needed
	// t.Logf("Create Room Response: %v", roomResp)

	// In ChatwMeX, create room usually returns the whole room object or specific structure
	// Let's handle potential ID field name differences ("_id", "id")
	var roomID string
	
	// Check if ID is at top level
	if id, ok := roomResp["id"].(string); ok {
		roomID = id
	} else if id, ok := roomResp["_id"].(string); ok {
		roomID = id
	} else if roomData, ok := roomResp["room"].(map[string]interface{}); ok {
		// 🔥 Found "room" object in response
		if id, ok := roomData["id"].(string); ok {
			roomID = id
		} else if id, ok := roomData["_id"].(string); ok {
			roomID = id
		}
	} else if data, ok := roomResp["data"].(map[string]interface{}); ok {
		// Sometimes wrapped in "data"
		if id, ok := data["id"].(string); ok {
			roomID = id
		}
	}

	if roomID == "" {
		t.Fatalf("Failed to extract room ID from response: %v", roomResp)
	}

	// 2. Send Message (HTTP Fallback)
	msgPayload := map[string]interface{}{
		"content": "Hello World",
		"type": "text",
	}
	msgBytes, _ := json.Marshal(msgPayload)
	reqMsg, _ := http.NewRequest("POST", fmt.Sprintf("/api/v1/rooms/%s/messages", roomID), bytes.NewBuffer(msgBytes))
	reqMsg.Header.Set("Authorization", authToken)
	reqMsg.Header.Set("Content-Type", "application/json")

	respMsg := executeRequest(reqMsg)
	
	// If failed, print body
	if respMsg.Code != http.StatusCreated {
		t.Logf("Send Message Error Response: %s", respMsg.Body.String())
	}
	assert.Equal(t, http.StatusCreated, respMsg.Code)
}
