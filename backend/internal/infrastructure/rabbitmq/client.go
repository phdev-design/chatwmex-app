package rabbitmq

import (
	"encoding/json"
	"fmt"
	"log"

	"chatwmex_backend/internal/config"
	"chatwmex_backend/internal/domain"

	amqp "github.com/rabbitmq/amqp091-go"
)

const (
	ExchangeName       = "chat_fanout"
	EventsExchangeName = "chat_events_exchange"
	QueueName          = "" // Empty for exclusive queue (auto-delete)
)

type RabbitMQClient struct {
	conn           *amqp.Connection
	channel        *amqp.Channel
	queueName      string
	eventQueueName string
	msgChan        chan<- *domain.Message
	eventChan      chan<- []byte
}

// NewRabbitMQClient initializes RabbitMQ connection and sets up exchange/queue.
func NewRabbitMQClient(cfg *config.Config, msgChan chan<- *domain.Message, eventChan chan<- []byte) (*RabbitMQClient, error) {
	conn, err := amqp.Dial(cfg.RabbitMQURL)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to RabbitMQ: %w", err)
	}

	ch, err := conn.Channel()
	if err != nil {
		conn.Close()
		return nil, fmt.Errorf("failed to open a channel: %w", err)
	}

	// 1. Declare Fanout Exchange
	err = ch.ExchangeDeclare(
		ExchangeName, // name
		"fanout",     // type
		true,         // durable
		false,        // auto-deleted
		false,        // internal
		false,        // no-wait
		nil,          // arguments
	)
	if err != nil {
		ch.Close()
		conn.Close()
		return nil, fmt.Errorf("failed to declare exchange: %w", err)
	}

	err = ch.ExchangeDeclare(
		EventsExchangeName,
		"fanout",
		true,
		false,
		false,
		false,
		nil,
	)
	if err != nil {
		ch.Close()
		conn.Close()
		return nil, fmt.Errorf("failed to declare events exchange: %w", err)
	}

	// 2. Declare Exclusive Queue (Unique for this server instance)
	q, err := ch.QueueDeclare(
		QueueName, // name (empty = server generated)
		false,     // durable
		true,      // delete when unused
		true,      // exclusive
		false,     // no-wait
		nil,       // arguments
	)
	if err != nil {
		ch.Close()
		conn.Close()
		return nil, fmt.Errorf("failed to declare queue: %w", err)
	}

	eventQ, err := ch.QueueDeclare(
		QueueName,
		false,
		true,
		true,
		false,
		nil,
	)
	if err != nil {
		ch.Close()
		conn.Close()
		return nil, fmt.Errorf("failed to declare event queue: %w", err)
	}

	// 3. Bind Queue to Exchange
	err = ch.QueueBind(
		q.Name,       // queue name
		"",           // routing key
		ExchangeName, // exchange
		false,
		nil,
	)
	if err != nil {
		ch.Close()
		conn.Close()
		return nil, fmt.Errorf("failed to bind queue: %w", err)
	}

	err = ch.QueueBind(
		eventQ.Name,
		"",
		EventsExchangeName,
		false,
		nil,
	)
	if err != nil {
		ch.Close()
		conn.Close()
		return nil, fmt.Errorf("failed to bind event queue: %w", err)
	}

	client := &RabbitMQClient{
		conn:           conn,
		channel:        ch,
		queueName:      q.Name,
		eventQueueName: eventQ.Name,
		msgChan:        msgChan,
		eventChan:      eventChan,
	}

	// Start consuming in a goroutine
	go client.consume()
	if eventChan != nil {
		go client.consumeEvents()
	}

	return client, nil
}

// Publish broadcasts a message to the fanout exchange.
func (c *RabbitMQClient) Publish(msg *domain.Message) error {
	body, err := json.Marshal(msg)
	if err != nil {
		return err
	}

	err = c.channel.Publish(
		ExchangeName, // exchange
		"",           // routing key
		false,        // mandatory
		false,        // immediate
		amqp.Publishing{
			ContentType: "application/json",
			Body:        body,
		})
	return err
}

func (c *RabbitMQClient) PublishEvent(event interface{}) error {
	body, err := json.Marshal(event)
	if err != nil {
		return err
	}

	return c.channel.Publish(
		EventsExchangeName,
		"",
		false,
		false,
		amqp.Publishing{
			ContentType: "application/json",
			Body:        body,
		},
	)
}

// consume reads messages from the queue and sends them to the msgChan.
func (c *RabbitMQClient) consume() {
	msgs, err := c.channel.Consume(
		c.queueName, // queue
		"",          // consumer
		true,        // auto-ack
		false,       // exclusive
		false,       // no-local
		false,       // no-wait
		nil,         // args
	)
	if err != nil {
		log.Printf("Failed to register a consumer: %v", err)
		return
	}

	for d := range msgs {
		var msg domain.Message
		if err := json.Unmarshal(d.Body, &msg); err != nil {
			log.Printf("Error decoding RabbitMQ message: %v", err)
			continue
		}
		// Send to Hub for local broadcast
		c.msgChan <- &msg
	}
}

func (c *RabbitMQClient) consumeEvents() {
	msgs, err := c.channel.Consume(
		c.eventQueueName,
		"",
		true,
		false,
		false,
		false,
		nil,
	)
	if err != nil {
		log.Printf("Failed to register event consumer: %v", err)
		return
	}

	for d := range msgs {
		if c.eventChan != nil {
			c.eventChan <- d.Body
		}
	}
}

// Close closes the RabbitMQ connection.
func (c *RabbitMQClient) Close() {
	if c.channel != nil {
		c.channel.Close()
	}
	if c.conn != nil {
		c.conn.Close()
	}
}
