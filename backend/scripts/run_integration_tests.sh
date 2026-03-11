#!/bin/bash

# Script to run RabbitMQ integration tests with Docker
# Usage: ./scripts/run_integration_tests.sh

set -e

CONTAINER_NAME="rabbitmq-test-$(date +%s)"
RABBITMQ_PORT=5672
MANAGEMENT_PORT=15672

echo "🐰 Starting RabbitMQ container..."
docker run -d --name "$CONTAINER_NAME" \
  -p $RABBITMQ_PORT:5672 \
  -p $MANAGEMENT_PORT:15672 \
  rabbitmq:3-management

echo "⏳ Waiting for RabbitMQ to be ready..."
sleep 10

# Check if RabbitMQ is ready
MAX_RETRIES=30
RETRY_COUNT=0
until docker exec "$CONTAINER_NAME" rabbitmq-diagnostics -q ping 2>/dev/null; do
  RETRY_COUNT=$((RETRY_COUNT + 1))
  if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
    echo "❌ RabbitMQ failed to start after $MAX_RETRIES attempts"
    docker logs "$CONTAINER_NAME"
    docker stop "$CONTAINER_NAME"
    docker rm "$CONTAINER_NAME"
    exit 1
  fi
  echo "   Waiting... (attempt $RETRY_COUNT/$MAX_RETRIES)"
  sleep 2
done

echo "✅ RabbitMQ is ready!"
echo "📊 Management UI available at: http://localhost:$MANAGEMENT_PORT (guest/guest)"
echo ""

# Run the tests
echo "🧪 Running integration tests..."
if go test -v ./internal/infrastructure/rabbitmq -run TestIntegration; then
  echo ""
  echo "✅ All integration tests passed!"
  TEST_EXIT_CODE=0
else
  echo ""
  echo "❌ Some integration tests failed!"
  TEST_EXIT_CODE=1
fi

# Cleanup
echo ""
echo "🧹 Cleaning up..."
docker stop "$CONTAINER_NAME" > /dev/null
docker rm "$CONTAINER_NAME" > /dev/null
echo "✅ Cleanup complete"

exit $TEST_EXIT_CODE
