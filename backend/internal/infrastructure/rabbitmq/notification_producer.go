package rabbitmq

import (
	"context"
	"encoding/json"
	"fmt"
	"log"

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
}

// NewNotificationProducer creates a new notification producer
func NewNotificationProducer(cfg *config.Config) (domain.NotificationProducer, error) {
	conn, err := amqp.Dial(cfg.RabbitMQURL)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to RabbitMQ: %w", err)
	}

	ch, err := conn.Channel()
	if err != nil {
		conn.Close()
		return nil, fmt.Errorf("failed to open a channel: %w", err)
	}

	// Declare Dead Letter Exchange
	err = ch.ExchangeDeclare(
		NotificationDLX, // name
		"direct",        // type
		true,            // durable
		false,           // auto-deleted
		false,           // internal
		false,           // no-wait
		nil,             // arguments
	)
	if err != nil {
		ch.Close()
		conn.Close()
		return nil, fmt.Errorf("failed to declare DLX: %w", err)
	}

	// Declare Dead Letter Queue
	_, err = ch.QueueDeclare(
		NotificationDLQ, // name
		true,            // durable
		false,           // delete when unused
		false,           // exclusive
		false,           // no-wait
		nil,             // arguments
	)
	if err != nil {
		ch.Close()
		conn.Close()
		return nil, fmt.Errorf("failed to declare DLQ: %w", err)
	}

	// Bind DLQ to DLX
	err = ch.QueueBind(
		NotificationDLQ, // queue name
		NotificationDLQ, // routing key
		NotificationDLX, // exchange
		false,
		nil,
	)
	if err != nil {
		ch.Close()
		conn.Close()
		return nil, fmt.Errorf("failed to bind DLQ: %w", err)
	}

	// Declare main notification queue with DLX configuration
	_, err = ch.QueueDeclare(
		NotificationQueueName, // name
		true,                  // durable
		false,                 // delete when unused
		false,                 // exclusive
		false,                 // no-wait
		amqp.Table{
			"x-dead-letter-exchange":    NotificationDLX,
			"x-dead-letter-routing-key": NotificationDLQ,
			"x-message-ttl":             300000, // 5 minutes
		},
	)
	if err != nil {
		ch.Close()
		conn.Close()
		return nil, fmt.Errorf("failed to declare notification queue: %w", err)
	}

	log.Printf("NotificationProducer initialized: queue=%s", NotificationQueueName)

	return &NotificationProducerImpl{
		conn:      conn,
		channel:   ch,
		queueName: NotificationQueueName,
	}, nil
}

// Publish sends a notification message to the queue
func (p *NotificationProducerImpl) Publish(ctx context.Context, msg *domain.PushNotificationMessage) error {
	body, err := json.Marshal(msg)
	if err != nil {
		log.Printf("[NotificationProducer] Failed to serialize notification message: %v", err)
		return fmt.Errorf("serialization error: %w", err)
	}

	err = p.channel.PublishWithContext(
		ctx,
		"",           // exchange
		p.queueName,  // routing key
		false,        // mandatory
		false,        // immediate
		amqp.Publishing{
			ContentType:  "application/json",
			Body:         body,
			DeliveryMode: amqp.Persistent, // Survive broker restarts
		},
	)

	if err != nil {
		log.Printf("[NotificationProducer] Failed to publish notification to queue: %v", err)
		return fmt.Errorf("publish error: %w", err)
	}

	return nil
}

// Close gracefully shuts down the producer
func (p *NotificationProducerImpl) Close() error {
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
