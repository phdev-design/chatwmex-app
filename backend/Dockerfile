# Build stage
FROM golang:1.23-alpine AS builder

WORKDIR /app

# Install dependencies
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build the application
RUN CGO_ENABLED=0 GOOS=linux go build -o server cmd/server/main.go

# Final stage
FROM alpine:latest

WORKDIR /app

# Install CA certificates for external HTTPS requests
RUN apk --no-cache add ca-certificates

# Copy the binary from builder
COPY --from=builder /app/server .

# Copy config files if needed (or rely on ENV vars)
# COPY --from=builder /app/configs ./configs
# We will mount configs or use ENV vars in docker-compose

# Expose port
EXPOSE 8080

# Command to run the executable
CMD ["./server"]
