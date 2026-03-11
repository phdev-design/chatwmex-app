# RabbitMQ Integration Tests

This directory contains integration tests for the async push notification system using RabbitMQ.

## Test Coverage

The integration tests validate the following scenarios:

1. **End-to-End Notification Flow** (`TestIntegration_EndToEndNotificationFlow`)
   - Validates: Requirements 3.1, 4.1, 4.3, 4.4
   - Tests the complete flow: Producer → RabbitMQ → Consumer → OneSignal
   - Verifies that messages are correctly published, consumed, and processed

2. **Message Serialization Round-Trip** (`TestIntegration_MessageSerializationRoundTrip`)
   - Property 1: Notification Message Serialization Round-Trip
   - Validates: Requirements 3.2, 4.2
   - Tests JSON serialization/deserialization preserves all fields
   - Includes Unicode characters and nested data structures

3. **Consumer Error Handling** (`TestIntegration_ConsumerErrorHandling`)
   - Validates: Requirements 5.1, 5.3
   - Tests retry logic for transient errors
   - Verifies error logging and NACK behavior

4. **Multiple Concurrent Messages** (`TestIntegration_MultipleMessages`)
   - Validates: Requirements 3.1, 4.1
   - Tests handling of multiple messages in parallel
   - Verifies queue throughput and message ordering

5. **Graceful Shutdown** (`TestIntegration_GracefulShutdown`)
   - Validates: Requirements 2.3, 7.4
   - Tests proper cleanup of producer and consumer
   - Verifies connections are closed gracefully

## Prerequisites

To run these integration tests, you need:

1. **RabbitMQ Server** running locally or accessible via network
   - Default connection: `amqp://guest:guest@localhost:5672/`
   - You can modify the connection string in the test configuration

2. **Go Testing Tools**
   - testify library (already included in go.mod)

## Running the Tests

### Option 1: Run with Local RabbitMQ

If you have RabbitMQ running locally:

```bash
# Run all integration tests
go test -v ./internal/infrastructure/rabbitmq -run TestIntegration

# Run a specific test
go test -v ./internal/infrastructure/rabbitmq -run TestIntegration_EndToEndNotificationFlow
```

### Option 2: Start RabbitMQ with Docker

If you don't have RabbitMQ installed, use Docker:

```bash
# Start RabbitMQ container
docker run -d --name rabbitmq-test \
  -p 5672:5672 \
  -p 15672:15672 \
  rabbitmq:3-management

# Wait a few seconds for RabbitMQ to start
sleep 5

# Run the tests
go test -v ./internal/infrastructure/rabbitmq -run TestIntegration

# Stop and remove the container when done
docker stop rabbitmq-test
docker rm rabbitmq-test
```

### Option 3: Skip Integration Tests

If RabbitMQ is not available, the tests will automatically skip:

```bash
go test -v ./internal/infrastructure/rabbitmq
```

Output will show:
```
--- SKIP: TestIntegration_EndToEndNotificationFlow (0.00s)
    integration_test.go:38: Skipping integration test: RabbitMQ not available
```

## Test Configuration

To use a different RabbitMQ server, modify the `cfg.RabbitMQURL` in the test files:

```go
cfg := &config.Config{
    RabbitMQURL: "amqp://user:password@your-rabbitmq-host:5672/",
}
```

## Continuous Integration

For CI/CD pipelines, you can:

1. **Use Docker Compose** to start RabbitMQ before tests
2. **Use testcontainers-go** for automatic container management
3. **Skip integration tests** in environments without RabbitMQ

Example CI configuration:

```yaml
# .github/workflows/test.yml
services:
  rabbitmq:
    image: rabbitmq:3-management
    ports:
      - 5672:5672
    options: >-
      --health-cmd "rabbitmq-diagnostics -q ping"
      --health-interval 10s
      --health-timeout 5s
      --health-retries 5
```

## Troubleshooting

### Connection Refused Error

If you see `connection refused`, ensure:
- RabbitMQ is running: `docker ps` or `systemctl status rabbitmq-server`
- Port 5672 is accessible: `telnet localhost 5672`
- Firewall allows connections

### Tests Timeout

If tests hang:
- Check RabbitMQ logs: `docker logs rabbitmq-test`
- Verify queue is being created: Access management UI at http://localhost:15672
- Increase timeout in test context if needed

### Mock Expectations Not Met

If mock assertions fail:
- Check consumer is actually processing messages
- Verify queue name matches between producer and consumer
- Ensure consumer has enough time to process (adjust sleep durations)

## Best Practices

1. **Always use timeouts** in test contexts to prevent hanging
2. **Clean up resources** with defer statements
3. **Use meaningful test data** that represents real-world scenarios
4. **Test both success and failure paths**
5. **Verify graceful shutdown** to prevent resource leaks

## Related Documentation

- [RabbitMQ Go Client Documentation](https://pkg.go.dev/github.com/rabbitmq/amqp091-go)
- [Testify Documentation](https://pkg.go.dev/github.com/stretchr/testify)
- [Design Document](../../../.kiro/specs/async-push-notification-rabbitmq/design.md)
- [Requirements Document](../../../.kiro/specs/async-push-notification-rabbitmq/requirements.md)
