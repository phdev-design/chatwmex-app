package rabbitmq

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"strings"

	"chatwmex_backend/internal/config"
	"chatwmex_backend/internal/domain"

	amqp "github.com/rabbitmq/amqp091-go"
)

// NotificationConsumer consumes notification messages from the queue and processes them
type NotificationConsumer struct {
	conn             *amqp.Connection
	channel          *amqp.Channel
	queueName        string
	oneSignalService domain.PushNotificationService
	maxRetries       int
	stopChan         chan struct{}
}

// NewNotificationConsumer creates a new notification consumer
func NewNotificationConsumer(
	cfg *config.Config,
	oneSignalService domain.PushNotificationService,
) (*NotificationConsumer, error) {
	conn, err := amqp.Dial(cfg.RabbitMQURL)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to RabbitMQ: %w", err)
	}

	ch, err := conn.Channel()
	if err != nil {
		conn.Close()
		return nil, fmt.Errorf("failed to open a channel: %w", err)
	}

	// Set QoS to process one message at a time
	err = ch.Qos(
		1,     // prefetch count
		0,     // prefetch size
		false, // global
	)
	if err != nil {
		ch.Close()
		conn.Close()
		return nil, fmt.Errorf("failed to set QoS: %w", err)
	}

	log.Printf("NotificationConsumer initialized: queue=%s", NotificationQueueName)

	return &NotificationConsumer{
		conn:             conn,
		channel:          ch,
		queueName:        NotificationQueueName,
		oneSignalService: oneSignalService,
		maxRetries:       3,
		stopChan:         make(chan struct{}),
	}, nil
}

// Start begins consuming messages from the queue
func (c *NotificationConsumer) Start(ctx context.Context) error {
	msgs, err := c.channel.Consume(
		c.queueName, // queue
		"",          // consumer
		false,       // auto-ack (manual ack for reliability)
		false,       // exclusive
		false,       // no-local
		false,       // no-wait
		nil,         // args
	)
	if err != nil {
		return fmt.Errorf("failed to register a consumer: %w", err)
	}

	log.Printf("[NotificationConsumer] Started consuming from queue: %s", c.queueName)

	go func() {
		for {
			select {
			case <-ctx.Done():
				log.Println("[NotificationConsumer] Context cancelled, stopping consumer")
				return
			case <-c.stopChan:
				log.Println("[NotificationConsumer] Stop signal received, stopping consumer")
				return
			case d, ok := <-msgs:
				if !ok {
					log.Println("[NotificationConsumer] Channel closed, stopping consumer")
					return
				}
				c.processMessage(d)
			}
		}
	}()

	return nil
}

// processMessage handles a single notification message
func (c *NotificationConsumer) processMessage(delivery amqp.Delivery) {
	// Check retry count
	retryCount := c.getRetryCount(delivery)
	if retryCount >= c.maxRetries {
		log.Printf("[NotificationConsumer] Max retries exceeded for notification message, sending to DLQ")
		delivery.Nack(false, false) // Send to DLQ
		return
	}

	var msg domain.PushNotificationMessage

	// Deserialization errors - permanent failure
	if err := json.Unmarshal(delivery.Body, &msg); err != nil {
		log.Printf("[NotificationConsumer] Failed to deserialize notification message: %v, body: %s",
			err, string(delivery.Body))
		delivery.Nack(false, false) // Don't requeue - bad message
		return
	}

	// Validation errors - permanent failure
	if len(msg.PlayerIDs) == 0 {
		log.Printf("[NotificationConsumer] Invalid notification message: no player IDs")
		delivery.Nack(false, false) // Don't requeue
		return
	}

	// OneSignal delivery
	err := c.oneSignalService.SendNotificationToDevices(
		msg.PlayerIDs,
		msg.Title,
		msg.Content,
		msg.Data,
	)

	if err != nil {
		if c.isTransientError(err) {
			// Transient error - retry
			log.Printf("[NotificationConsumer] Transient error sending notification (will retry): error=%v, retryCount=%d, playerIDs=%v",
				err, retryCount, msg.PlayerIDs)
			delivery.Nack(false, true) // Requeue for retry
		} else {
			// Permanent error - don't retry
			log.Printf("[NotificationConsumer] Permanent error sending notification: error=%v, playerIDs=%v",
				err, msg.PlayerIDs)
			delivery.Nack(false, false) // Send to DLQ
		}
		return
	}

	// Success
	delivery.Ack(false)
	log.Printf("[NotificationConsumer] Successfully processed notification: playerIDs=%v, title=%s",
		msg.PlayerIDs, msg.Title)
}

// getRetryCount extracts the retry count from message headers
func (c *NotificationConsumer) getRetryCount(delivery amqp.Delivery) int {
	retryCount := 0
	if xDeath, ok := delivery.Headers["x-death"].([]interface{}); ok && len(xDeath) > 0 {
		if death, ok := xDeath[0].(amqp.Table); ok {
			if count, ok := death["count"].(int64); ok {
				retryCount = int(count)
			}
		}
	}
	return retryCount
}

// isTransientError determines if an error is transient and should be retried
func (c *NotificationConsumer) isTransientError(err error) bool {
	// Network timeouts, 5xx errors are transient
	// 4xx errors (bad request) are permanent
	errStr := err.Error()
	return strings.Contains(errStr, "timeout") ||
		strings.Contains(errStr, "connection refused") ||
		strings.Contains(errStr, "500") ||
		strings.Contains(errStr, "502") ||
		strings.Contains(errStr, "503") ||
		strings.Contains(errStr, "504")
}

// Stop gracefully stops the consumer
func (c *NotificationConsumer) Stop() error {
	close(c.stopChan)

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
