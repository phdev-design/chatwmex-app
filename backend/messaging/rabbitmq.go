package messaging

import (
	"context"
	"fmt"
	"log"
	"time"

	amqp "github.com/rabbitmq/amqp091-go"
)

// RabbitMQClient wraps the AMQP connection and channel
type RabbitMQClient struct {
	Conn    *amqp.Connection
	Channel *amqp.Channel
}

// NewRabbitMQClient connects to RabbitMQ and opens a channel
func NewRabbitMQClient(url string) (*RabbitMQClient, error) {
	var conn *amqp.Connection
	var err error

	// Retry logic for RabbitMQ connection
	for i := 0; i < 5; i++ {
		conn, err = amqp.Dial(url)
		if err == nil {
			break
		}
		log.Printf("Failed to connect to RabbitMQ (attempt %d/5): %v", i+1, err)
		time.Sleep(2 * time.Second)
	}

	if err != nil {
		return nil, fmt.Errorf("failed to connect to RabbitMQ after retries: %v", err)
	}

	ch, err := conn.Channel()
	if err != nil {
		conn.Close()
		return nil, fmt.Errorf("failed to open a channel: %v", err)
	}

	// Declare exchanges/queues if needed here, or let services do it
	err = ch.ExchangeDeclare(
		"chat_events", // name
		"topic",       // type
		true,          // durable
		false,         // auto-deleted
		false,         // internal
		false,         // no-wait
		nil,           // arguments
	)
	if err != nil {
		ch.Close()
		conn.Close()
		return nil, fmt.Errorf("failed to declare exchange: %v", err)
	}

	log.Printf("✓ RabbitMQ connected")
	return &RabbitMQClient{
		Conn:    conn,
		Channel: ch,
	}, nil
}

// PublishMessage publishes a message to the exchange
func (r *RabbitMQClient) PublishMessage(ctx context.Context, routingKey string, body []byte) error {
	return r.Channel.PublishWithContext(ctx,
		"chat_events", // exchange
		routingKey,    // routing key
		false,         // mandatory
		false,         // immediate
		amqp.Publishing{
			ContentType: "application/json",
			Body:        body,
			Timestamp:   time.Now(),
		})
}

// Close closes the connection and channel
func (r *RabbitMQClient) Close() {
	if r.Channel != nil {
		r.Channel.Close()
	}
	if r.Conn != nil {
		r.Conn.Close()
	}
}
