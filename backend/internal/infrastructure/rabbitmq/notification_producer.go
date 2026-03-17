package rabbitmq

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"sync"

	"chatwmex_backend/internal/config"
	"chatwmex_backend/internal/domain"

	amqp "github.com/rabbitmq/amqp091-go"
)

const (
	NotificationQueueName = "notification_queue"
	NotificationDLX       = "notification_dlx"
	NotificationDLQ       = "notification_dlq"
)

// NotificationProducerImpl implements the NotificationProducer interface
type NotificationProducerImpl struct {
	conn      *amqp.Connection
	channel   *amqp.Channel
	queueName string
	cfg       *config.Config
	mu        sync.Mutex
}

// NewNotificationProducer creates a new notification producer
func NewNotificationProducer(cfg *config.Config) (domain.NotificationProducer, error) {
	p := &NotificationProducerImpl{
		queueName: NotificationQueueName,
		cfg:       cfg,
	}
	if err := p.connect(); err != nil {
		return nil, err
	}
	log.Printf("NotificationProducer initialized: queue=%s", NotificationQueueName)
	return p, nil
}

// connect establishes a new AMQP connection, channel, and declares all queues/exchanges.
// Must be called with mu held OR before the struct is shared across goroutines.
func (p *NotificationProducerImpl) connect() error {
	conn, err := amqp.Dial(p.cfg.RabbitMQURL)
	if err != nil {
		return fmt.Errorf("failed to connect to RabbitMQ: %w", err)
	}

	ch, err := conn.Channel()
	if err != nil {
		conn.Close()
		return fmt.Errorf("failed to open channel: %w", err)
	}

	if err := declareNotificationTopology(ch); err != nil {
		ch.Close()
		conn.Close()
		return err
	}

	p.conn = conn
	p.channel = ch
	return nil
}

// reconnect closes stale resources and re-establishes the connection.
// Must be called with mu held.
func (p *NotificationProducerImpl) reconnect() error {
	// Clean up stale resources (ignore errors — they may already be closed)
	if p.channel != nil {
		p.channel.Close()
		p.channel = nil
	}
	if p.conn != nil {
		p.conn.Close()
		p.conn = nil
	}

	log.Println("[NotificationProducer] Reconnecting to RabbitMQ...")
	if err := p.connect(); err != nil {
		return fmt.Errorf("reconnect failed: %w", err)
	}
	log.Println("[NotificationProducer] Reconnected successfully")
	return nil
}

// isHealthy reports whether the current connection and channel are usable.
// Must be called with mu held.
func (p *NotificationProducerImpl) isHealthy() bool {
	return p.conn != nil && !p.conn.IsClosed() && p.channel != nil
}

// Publish sends a notification message to the queue.
// It automatically reconnects once on failure before giving up.
func (p *NotificationProducerImpl) Publish(ctx context.Context, msg *domain.PushNotificationMessage) error {
	body, err := json.Marshal(msg)
	if err != nil {
		return fmt.Errorf("serialization error: %w", err)
	}

	p.mu.Lock()
	defer p.mu.Unlock()

	// Ensure connection is healthy before attempting publish
	if !p.isHealthy() {
		if err := p.reconnect(); err != nil {
			return err
		}
	}

	publishing := amqp.Publishing{
		ContentType:  "application/json",
		Body:         body,
		DeliveryMode: amqp.Persistent,
	}

	err = p.channel.PublishWithContext(ctx, "", p.queueName, false, false, publishing)
	if err != nil {
		log.Printf("[NotificationProducer] Publish failed (%v), attempting reconnect + retry", err)
		if reconnErr := p.reconnect(); reconnErr != nil {
			return fmt.Errorf("publish failed and reconnect failed: %w", err)
		}
		if retryErr := p.channel.PublishWithContext(ctx, "", p.queueName, false, false, publishing); retryErr != nil {
			log.Printf("[NotificationProducer] Retry also failed: %v", retryErr)
			return fmt.Errorf("publish error after retry: %w", retryErr)
		}
		log.Println("[NotificationProducer] Publish succeeded after reconnect")
	}

	return nil
}

// Close gracefully shuts down the producer
func (p *NotificationProducerImpl) Close() error {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.channel != nil {
		if err := p.channel.Close(); err != nil {
			log.Printf("[NotificationProducer] Error closing channel: %v", err)
		}
	}
	if p.conn != nil {
		if err := p.conn.Close(); err != nil {
			log.Printf("[NotificationProducer] Error closing connection: %v", err)
			return err
		}
	}
	log.Println("[NotificationProducer] Closed gracefully")
	return nil
}

// declareNotificationTopology declares the DLX, DLQ, and main notification queue.
func declareNotificationTopology(ch *amqp.Channel) error {
	if err := ch.ExchangeDeclare(
		NotificationDLX, "direct", true, false, false, false, nil,
	); err != nil {
		return fmt.Errorf("failed to declare DLX: %w", err)
	}

	if _, err := ch.QueueDeclare(
		NotificationDLQ, true, false, false, false, nil,
	); err != nil {
		return fmt.Errorf("failed to declare DLQ: %w", err)
	}

	if err := ch.QueueBind(
		NotificationDLQ, NotificationDLQ, NotificationDLX, false, nil,
	); err != nil {
		return fmt.Errorf("failed to bind DLQ: %w", err)
	}

	if _, err := ch.QueueDeclare(
		NotificationQueueName, true, false, false, false,
		amqp.Table{
			"x-dead-letter-exchange":    NotificationDLX,
			"x-dead-letter-routing-key": NotificationDLQ,
			"x-message-ttl":             int32(300000), // 5 minutes
		},
	); err != nil {
		return fmt.Errorf("failed to declare notification queue: %w", err)
	}

	return nil
}
