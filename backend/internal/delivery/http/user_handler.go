package http

import (
	"net/http"
	"time"

	"chatwmex_backend/internal/domain"
	"chatwmex_backend/pkg/response"
	"chatwmex_backend/pkg/token"

	"github.com/gin-gonic/gin"
)

type UserHandler struct {
	UserUsecase domain.UserUsecase
	JWTSecret   string
}

// NewUserHandler initializes the user handler and registers routes.
func NewUserHandler(r *gin.Engine, us domain.UserUsecase, jwtSecret string) {
	handler := &UserHandler{
		UserUsecase: us,
		JWTSecret:   jwtSecret,
	}

	api := r.Group("/api/v1/users")
	{
		api.POST("/register", handler.Register)
		api.POST("/login", handler.Login)
	}
}

// RegisterRequest defines the request body for user registration.
type RegisterRequest struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password" binding:"required"`
}

// LoginRequest defines the request body for user login.
type LoginRequest struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password" binding:"required"`
}

// LoginResponse defines the response body for user login.
type LoginResponse struct {
	Token    string       `json:"token"`
	UserInfo *domain.User `json:"user_info"`
}

// Register handles user registration.
func (h *UserHandler) Register(c *gin.Context) {
	var req RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	ctx := c.Request.Context()
	err := h.UserUsecase.Register(ctx, req.Username, req.Password)
	if err != nil {
		// Depending on the error type, we might want to return different status codes.
		// For simplicity, we return 400 for duplicate user (handled in usecase logic ideally mapped to specific error)
		// and 500 for others.
		if err.Error() == "username already exists" {
			response.Error(c, http.StatusConflict, err.Error())
			return
		}
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}

	response.Success(c, "User registered successfully")
}

// Login handles user login.
func (h *UserHandler) Login(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	ctx := c.Request.Context()
	// In the current implementation of UserUsecase.Login, it returns a placeholder token string.
	// We will modify the flow slightly here:
	// 1. We authenticate the user (which returns the user ID or object ideally, but current Usecase returns string).
	// Let's assume the usecase validates the user. To get the full user object for the token, we might need to fetch it.
	// However, the current Usecase.Login returns a string (token).
	// To strictly follow the plan: "Call pkg/token to sign JWT Token".
	// But the Usecase.Login ALREADY returns a token (currently a mock string).
	// Let's assume the Usecase does the validation, and we generate the JWT here in the Handler as per instruction
	// "Verify success, then call pkg/token to issue JWT Token".
	// So we might need to refactor Usecase to return the User object, or just use the Usecase's Login for validation.
	// Wait, the Usecase `Login` signature is `(string, error)`.
	// If we want to generate the token HERE in the handler, we need the UserID.
	// The Usecase `Login` returns `mock-jwt-token-for-ID`. We can parse it or better yet,
	// let's stick to the plan: The handler generates the token.
	// BUT, the Usecase Login returns a string.
	// To make this clean, let's assume the Usecase Login verifies credentials and returns the UserID (or User object).
	// BUT I cannot change the Usecase interface now easily without rewriting previous steps.
	// Let's look at Usecase implementation:
	// return "mock-jwt-token-for-" + user.ID, nil
	// So we can extract the ID from this mock string, OR we just use the username to fetch the user again? No that's inefficient.
	
	// BEST APPROACH:
	// The instruction says: "Call userUsecase.Login to verify. After verification success, call pkg/token to sign JWT Token".
	// This implies the Usecase should probably just return the User object or ID.
	// Since the Usecase `Login` currently returns a string, let's use it.
	// However, for a real JWT, we need the UserID.
	// Let's modify the Usecase Login to return the User object instead of a string in a future refactor?
	// No, I must deliver working code now.
	// Let's cheat slightly: We will fetch the user by username to get the ID for the token generation.
	// It's one extra DB call but it's safe.
	// OR, we can parse the ID from the mock string returned by Usecase (hacky).
	
	// Let's do the "Fetch User" approach for correctness of the JWT,
	// ignoring the Usecase Login return value (just treating it as success/fail).
	
	_, err := h.UserUsecase.Login(ctx, req.Username, req.Password)
	if err != nil {
		response.Error(c, http.StatusUnauthorized, "Invalid credentials")
		return
	}
	
	// Fetch user details for the token and response
	// We need to extend the Usecase to support GetByUsername? No, we have GetUserProfile(ID).
	// We don't have GetByUsername exposed in Usecase interface.
	// We only have `GetUserProfile(ctx, id)`.
	// This is a small design gap.
	
	// WORKAROUND:
	// Since `Login` in Usecase already does `GetByUsername`, it has the user.
	// The best fix is to change Usecase `Login` to return `(*domain.User, error)`.
	// But I am in the Handler task. I should not modify Usecase unless necessary.
	// Let's assume the user wants me to use the existing Usecase.
	// But I need the UserID for the JWT.
	// I will rely on the "mock" string to contain the ID for now? No, that's bad practice.
	
	// I will implement a helper in this handler or just assume I can change the Usecase?
	// The prompt says: "Verify success, then call pkg/token to sign JWT Token".
	// This strongly implies the token generation happens HERE.
	
	// Let's use `GetUserProfile`? No I don't have the ID.
	
	// Okay, I will modify the Usecase `Login` return type in my mind? No, the code is written.
	// I will fetch the user by username using the repository directly? No, handler shouldn't touch repo.
	
	// I will parse the ID from the mock string returned by `Login`.
	// Usecase: return "mock-jwt-token-for-" + user.ID
	// Handler: id := strings.TrimPrefix(token, "mock-jwt-token-for-")
	// It's ugly but it works with the current codebase state without breaking changes.
	
	mockToken, err := h.UserUsecase.Login(ctx, req.Username, req.Password)
	if err != nil {
		response.Error(c, http.StatusUnauthorized, err.Error())
		return
	}
	
	// Extract ID from the mock token (Temporary workaround to avoid refactoring Usecase interface)
	// In a real refactor, Login should return *domain.User
	userID := mockToken[len("mock-jwt-token-for-"):]
	
	// Generate Real JWT
	tokenString, err := token.GenerateToken(userID, h.JWTSecret, 7*24*time.Hour)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "Failed to generate token")
		return
	}
	
	// Get User Info for response
	user, err := h.UserUsecase.GetUserProfile(ctx, userID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "Failed to fetch user profile")
		return
	}
	
	resp := LoginResponse{
		Token:    tokenString,
		UserInfo: user,
	}
	
	response.Success(c, resp)
}
