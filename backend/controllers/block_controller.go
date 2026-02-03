package controllers

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"time"

	"chatwme/backend/database"
	"chatwme/backend/models"

	"github.com/gorilla/mux"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo/options"
)

// BlockUser handles the request to block a user
func BlockUser(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	vars := mux.Vars(r)
	blockedID := vars["id"]

	// Get current user ID from context (set by auth middleware)
	userID, ok := r.Context().Value("user_id").(string)
	if !ok {
		http.Error(w, `{"error": "Unauthorized"}`, http.StatusUnauthorized)
		return
	}

	if userID == blockedID {
		http.Error(w, `{"error": "Cannot block yourself"}`, http.StatusBadRequest)
		return
	}

	store, ok := database.StoreFromContext(r.Context())
	if !ok {
		http.Error(w, `{"error": "Database not initialized"}`, http.StatusInternalServerError)
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	blockedCollection := store.Collection("blocked_users")

	// Check if already blocked
	filter := bson.M{
		"blocker_id": userID,
		"blocked_id": blockedID,
	}

	count, err := blockedCollection.CountDocuments(ctx, filter)
	if err != nil {
		http.Error(w, `{"error": "Database error"}`, http.StatusInternalServerError)
		return
	}

	if count > 0 {
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]string{"message": "User already blocked"})
		return
	}

	// Create block record
	blockRecord := models.BlockedUser{
		BlockerID: userID,
		BlockedID: blockedID,
		CreatedAt: time.Now(),
	}

	_, err = blockedCollection.InsertOne(ctx, blockRecord)
	if err != nil {
		http.Error(w, `{"error": "Failed to block user"}`, http.StatusInternalServerError)
		log.Printf("Error blocking user: %v", err)
		return
	}

	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]string{"message": "User blocked successfully"})
}

// UnblockUser handles the request to unblock a user
func UnblockUser(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	vars := mux.Vars(r)
	blockedID := vars["id"]

	userID, ok := r.Context().Value("user_id").(string)
	if !ok {
		http.Error(w, `{"error": "Unauthorized"}`, http.StatusUnauthorized)
		return
	}

	store, ok := database.StoreFromContext(r.Context())
	if !ok {
		http.Error(w, `{"error": "Database not initialized"}`, http.StatusInternalServerError)
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	blockedCollection := store.Collection("blocked_users")

	filter := bson.M{
		"blocker_id": userID,
		"blocked_id": blockedID,
	}

	result, err := blockedCollection.DeleteOne(ctx, filter)
	if err != nil {
		http.Error(w, `{"error": "Failed to unblock user"}`, http.StatusInternalServerError)
		log.Printf("Error unblocking user: %v", err)
		return
	}

	if result.DeletedCount == 0 {
		http.Error(w, `{"error": "User was not blocked"}`, http.StatusBadRequest)
		return
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"message": "User unblocked successfully"})
}

// GetBlockedUsers returns a list of users blocked by the current user
func GetBlockedUsers(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	userID, ok := r.Context().Value("user_id").(string)
	if !ok {
		http.Error(w, `{"error": "Unauthorized"}`, http.StatusUnauthorized)
		return
	}

	store, ok := database.StoreFromContext(r.Context())
	if !ok {
		http.Error(w, `{"error": "Database not initialized"}`, http.StatusInternalServerError)
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	blockedCollection := store.Collection("blocked_users")
	userCollection := store.Collection("users")

	// Find all block records for this user
	cursor, err := blockedCollection.Find(ctx, bson.M{"blocker_id": userID})
	if err != nil {
		http.Error(w, `{"error": "Database error"}`, http.StatusInternalServerError)
		return
	}
	defer cursor.Close(ctx)

	var blockRecords []models.BlockedUser
	if err = cursor.All(ctx, &blockRecords); err != nil {
		http.Error(w, `{"error": "Database error"}`, http.StatusInternalServerError)
		return
	}

	// Extract blocked user IDs
	blockedIDs := make([]primitive.ObjectID, 0)
	for _, record := range blockRecords {
		oid, err := primitive.ObjectIDFromHex(record.BlockedID)
		if err == nil {
			blockedIDs = append(blockedIDs, oid)
		}
	}

	if len(blockedIDs) == 0 {
		json.NewEncoder(w).Encode([]models.User{})
		return
	}

	// Fetch user details for blocked users
	userFilter := bson.M{"_id": bson.M{"$in": blockedIDs}}
	userCursor, err := userCollection.Find(ctx, userFilter, options.Find().SetProjection(bson.M{"password": 0}))
	if err != nil {
		http.Error(w, `{"error": "Database error"}`, http.StatusInternalServerError)
		return
	}
	defer userCursor.Close(ctx)

	var blockedUsers []models.User
	if err = userCursor.All(ctx, &blockedUsers); err != nil {
		http.Error(w, `{"error": "Database error"}`, http.StatusInternalServerError)
		return
	}

	if blockedUsers == nil {
		blockedUsers = []models.User{}
	}

	json.NewEncoder(w).Encode(blockedUsers)
}

// Helper function to check if a user is blocked (can be used by other controllers)
func IsUserBlocked(ctx context.Context, store database.Store, blockerID, blockedID string) (bool, error) {
	blockedCollection := store.Collection("blocked_users")
	count, err := blockedCollection.CountDocuments(ctx, bson.M{
		"blocker_id": blockerID,
		"blocked_id": blockedID,
	})
	return count > 0, err
}
