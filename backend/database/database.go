package database

import (
	"context"
	"log"

	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

type Store interface {
	Collection(collectionName string) *mongo.Collection
	Disconnect(ctx context.Context) error
}

type contextKey string

const storeContextKey contextKey = "store"

type MongoStore struct {
	client *mongo.Client
	dbName string
}

func NewMongoStore(ctx context.Context, uri string, dbName string) (*MongoStore, error) {
	clientOptions := options.Client().ApplyURI(uri)
	client, err := mongo.Connect(ctx, clientOptions)
	if err != nil {
		return nil, err
	}

	if err := client.Ping(ctx, nil); err != nil {
		return nil, err
	}

	log.Println("Successfully connected to MongoDB!")
	return &MongoStore{
		client: client,
		dbName: dbName,
	}, nil
}

func (s *MongoStore) Collection(collectionName string) *mongo.Collection {
	return s.client.Database(s.dbName).Collection(collectionName)
}

func (s *MongoStore) Disconnect(ctx context.Context) error {
	return s.client.Disconnect(ctx)
}

func ContextWithStore(ctx context.Context, store Store) context.Context {
	return context.WithValue(ctx, storeContextKey, store)
}

func StoreFromContext(ctx context.Context) (Store, bool) {
	store, ok := ctx.Value(storeContextKey).(Store)
	return store, ok
}
