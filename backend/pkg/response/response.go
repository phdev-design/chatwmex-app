package response

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

// Response represents the standard JSON response format.
type Response struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
	Data    any    `json:"data,omitempty"`
}

// Success sends a success response with the given data.
func Success(c *gin.Context, data any) {
	c.JSON(http.StatusOK, Response{
		Code:    http.StatusOK,
		Message: "success",
		Data:    data,
	})
}

// Error sends an error response with the given code and message.
// The HTTP status code is also set to the provided code if it's a valid HTTP status code,
// otherwise it defaults to 500 or 400 depending on context, but here we simply map code to status.
// Usually, 'code' in the body matches the HTTP status code.
func Error(c *gin.Context, code int, message string) {
	c.JSON(code, Response{
		Code:    code,
		Message: message,
		Data:    nil,
	})
}
