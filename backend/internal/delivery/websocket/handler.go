package websocket

import (
	"log"
	"net/http"

	"chatwmex_backend/pkg/token"

	"github.com/gin-gonic/gin"
)

// ServeWs handles websocket requests from the peer.
func ServeWs(hub *Hub, c *gin.Context, jwtSecret string) {
	// 1. Authenticate via Query Param "token"
	// Since standard WebSocket API cannot set custom headers easily, we use query param.
	tokenStr := c.Query("token")
	if tokenStr == "" {
		// Try to fallback to Auth Header if present (for non-browser clients)
		authHeader := c.GetHeader("Authorization")
		if len(authHeader) > 7 && authHeader[:7] == "Bearer " {
			tokenStr = authHeader[7:]
		} else {
			log.Println("WS Error: No token provided")
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
			return
		}
	}

	validatedToken, err := token.ValidateToken(tokenStr, jwtSecret)
	if err != nil || !validatedToken.Valid {
		log.Printf("WS Error: Invalid token: %v", err)
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	claims, ok := validatedToken.Claims.(*token.JWTClaims)
	if !ok {
		log.Println("WS Error: Invalid claims")
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	userID := claims.UserID

	// 2. Upgrade HTTP connection to WebSocket
	// Use c.Writer and c.Request directly
	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		log.Printf("WS Error: Failed to upgrade: %v", err)
		return
	}

	// 3. Create Client and Register to Hub
	client := &Client{
		hub:    hub,
		conn:   conn,
		send:   make(chan []byte, 256),
		userID: userID,
	}
	client.hub.register <- client

	// 4. Start Pumps in Goroutines
	go client.writePump()
	go client.readPump()
}
