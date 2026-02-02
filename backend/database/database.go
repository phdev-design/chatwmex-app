package database

import (
	"context"
	"log"
	"time"

	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

// MongoClient 是 MongoDB 的客戶端實例
var MongoClient *mongo.Client

// ConnectDB 連線到 MongoDB
func ConnectDB(uri string) error {
	var err error
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	clientOptions := options.Client().ApplyURI(uri)
	MongoClient, err = mongo.Connect(ctx, clientOptions)
	if err != nil {
		return err
	}

	// 檢查連線
	err = MongoClient.Ping(ctx, nil)
	if err != nil {
		return err
	}

	log.Println("Successfully connected to MongoDB!")
	return nil
}

// GetCollection 返回一個集合的實例
func GetCollection(collectionName string, dbName string) *mongo.Collection {
	return MongoClient.Database(dbName).Collection(collectionName)
}

// DisconnectDB 斷開與 MongoDB 的連線
func DisconnectDB() {
	if MongoClient != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := MongoClient.Disconnect(ctx); err != nil {
			log.Fatalf("Error disconnecting from MongoDB: %v", err)
		}
		log.Println("Disconnected from MongoDB.")
	}
}