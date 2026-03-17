package rabbitmq

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"strings"
	"sync"
	"time"

	"chatwmex_backend/internal/config"
	"chatwmex_backend/internal/domain"

	amqp "github.com/rabbitmq/amqp091-go"
)

// NotificationConsumer consumes notification messages from the queue and processes them
type NotificationConsumer struct {
	cfg              *config.Config
	conn             *amqp.Connection
	channel          *amqp.Channel
	queueName        string
	oneSignalService domain.PushNotificationService
	maxRetries       int
	stopChan         chan struct{}
	mu               sync.Mutex
}

// NewNotificationConsumer creates a new notification consumer
func NewNotificationConsumer(
	cfg *config.Config,
	oneSignalService domain.PushNotificationService,
) (*NotificationConsumer, error) {
	c := &NotificationConsumer{
		cfg:              cfg,
		queueName:        NotificationQueueName,
		oneSignalService: oneSignalService,
		maxRetries:       3,
		stopChan:         make(chan struct{}),
	}
	if err := c.connect(); err != nil {
		return nil, err
	}
	log.Printf("NotificationConsumer initialized: queue=%s", NotificationQueueName)
	return c, nil
}

// connect establishes a fresh AMQP connection and channel.
func (c *NotificationConsumer) connect() error {
	conn, err := amqp.Dial(c.cfg.RabbitMQURL)
	if err != nil {
		return fmt.Errorf("failed to connect to RabbitMQ: %w", err)
	}

	ch, err := conn.Channel()
	if err != nil {
		conn.Close()
		return fmt.Errorf("failed to open channel: %w", err)
	}

	if err := ch.Qos(1, 0, false); err != nil {
		ch.Close()
		conn.Close()
		return fmt.Errorf("failed to set QoS: %w", err)
	}

	c.conn = conn
	c.channel = ch
	return nil
}

// Start begins consuming messages from the queue.
// It automatically restarts the consumer loop if the channel closes unexpectedly.
func (c *NotificationConsumer) Start(ctx context.Context) error {
	go c.runLoop(ctx)
	return nil
}

// runLoop is the main consumer loop. It restarts itself on channel/connection failure.
func (c *NotificationConsumer) runLoop(ctx context.Context) {
	for {
		// Check if we've been asked to stop
		select {
		case <-c.stopChan:
			return
		case <-ctx.Done():
			return
		default:
		}

		msgs, closeChan, err := c.startConsuming()
		if err != nil {
			log.Printf("[NotificationConsumer] Failed to start consuming: %v — retrying in 5s", err)
			select {
			case <-time.After(5 * time.Second):
				c.reconnect()
				continue
			case <-c.stopChan:
				return
			case <-ctx.Done():
				return
			}
		}

		log.Printf("[NotificationConsumer] Started consuming from queue: %s", c.queueName)

		// Process messages until channel closes or stop is requested
		c.consumeMessages(ctx, msgs, closeChan)

		// If we exit consumeMessages without a stop signal, reconnect and retry
		select {
		case <-c.stopChan:
			return
		case <-ctx.Done():
			return
		default:
			log.Println("[NotificationConsumer] Channel closed unexpectedly, reconnecting in 3s...")
			time.Sleep(3 * time.Second)
			c.reconnect()
		}
	}
}

// startConsuming registers a consumer and returns the delivery channel and close notifier.
func (c *NotificationConsumer) startConsuming() (<-chan amqp.Delivery, <-chan *amqp.Error, error) {
	c.mu.Lock()
	defer c.mu.Unlock()

	msgs, err := c.channel.Consume(
		c.queueName, "", false, false, false, false, nil,
	)
	if err != nil {
		return nil, nil, err
	}

	closeChan := make(chan *amqp.Error, 1)
	c.channel.NotifyClose(closeChan)

	return msgs, closeChan, nil
}

// consumeMessages processes deliveries until the channel closes or stop is requested.
func (c *NotificationConsumer) consumeMessages(ctx context.Context, msgs <-chan amqp.Delivery, closeChan <-chan *amqp.Error) {
	for {
		select {
		case <-ctx.Done():
			return
		case <-c.stopChan:
			return
		case amqpErr, ok := <-closeChan:
			if !ok || amqpErr != nil {
				log.Printf("[NotificationConsumer] Channel closed (%v)", amqpErr)
				return
			}
		case d, ok := <-msgs:
			if !ok {
				log.Println("[NotificationConsumer] Delivery channel closed")
				return
			}
			c.processMessage(d)
		}
	}
}

// reconnect closes stale resources and re-establishes the connection.
func (c *NotificationConsumer) reconnect() {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.channel != nil {
		c.channel.Close()
		c.channel = nil
	}
	if c.conn != nil {
		c.conn.Close()
		c.conn = nil
	}

	log.Println("[NotificationConsumer] Reconnecting to RabbitMQ...")
	if err := c.connect(); err != nil {
		log.Printf("[NotificationConsumer] Reconnect failed: %v", err)
		return
	}
	log.Println("[NotificationConsumer] Reconnected successfully")
}

// processMessage handles a single notification message
func (c *NotificationConsumer) processMessage(delivery amqp.Delivery) {
	retryCount := c.getRetryCount(delivery)
	if retryCount >= c.maxRetries {
		log.Printf("[NotificationConsumer] Max retries exceeded, sending to DLQ")
		delivery.Nack(false, false)
		return
	}

	var msg domain.PushNotificationMessage
	if err := json.Unmarshal(delivery.Body, &msg); err != nil {
		log.Printf("[NotificationConsumer] Failed to deserialize message: %v", err)
		delivery.Nack(false, false)
		return
	}

	if len(msg.PlayerIDs) == 0 {
		log.Printf("[NotificationConsumer] Invalid message: no player IDs")
		delivery.Nack(false, false)
		return
	}

	err := c.oneSignalService.SendNotificationToDevices(
		msg.PlayerIDs, msg.Title, msg.Content, msg.Data,
	)
	if err != nil {
		if c.isTransientError(err) {
			log.Printf("[NotificationConsumer] Transient error (retry %d): %v", retryCount, err)
			delivery.Nack(false, true)
		} else {
			log.Printf("[NotificationConsumer] Permanent error: %v", err)
			delivery.Nack(false, false)
		}
		return
	}

	delivery.Ack(false)
	log.Printf("[NotificationConsumer] Notification sent: playerIDs=%v", msg.PlayerIDs)
}

// getRetryCount extracts the retry count from message headers
func (c *NotificationConsumer) getRetryCount(delivery amqp.Delivery) int {
	if xDeath, ok := delivery.Headers["x-death"].([]interface{}); ok && len(xDeath) > 0 {
		if death, ok := xDeath[0].(amqp.Table); ok {
			if count, ok := death["count"].(int64); ok {
				return int(count)
			}
		}
	}
	return 0
}

// isTransientError determines if an error is transient and should be retried
func (c *NotificationConsumer) isTransientError(err error) bool {
	s := err.Error()
	return strings.Contains(s, "timeout") ||
		strings.Contains(s, "connection refused") ||
		strings.Contains(s, "500") ||
		strings.Contains(s, "502") ||
		strings.Contains(s, "503") ||
		strings.Contains(s, "504")
}

// Stop gracefully stops the consumer
func (c *NotificationConsumer) Stop() error {
	close(c.stopChan)

	c.mu.Lock()
	defer c.mu.Unlock()

	if c.channel != nil {
		if err := c.channel.Close(); err != nil {
			log.Printf("[NotificationConsumer] Error closing channel: %v", err)
		}
	}
	if c.conn != nil {
		if err := c.conn.Close(); err != nil {
			log.Printf("[NotificationConsumer] Error closing connection: %v", err)
			return err
		}
	}
	log.Println("[NotificationConsumer] Stopped gracefully")
	return nil
}
