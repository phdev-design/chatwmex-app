package utils

import (
	"fmt"
	"time"

	"chatwme/backend/config"

	"github.com/golang-jwt/jwt/v5"
)

// Claims 定義了 JWT 的聲明 (payload)
type Claims struct {
	UserID   string `json:"user_id"`
	Username string `json:"username"`
	jwt.RegisteredClaims
}

// GenerateJWT 根據使用者 ID 和用戶名稱生成一個 JWT
func GenerateJWT(userID, username string) (string, error) {
	cfg := config.LoadConfig()
	jwtSecret := []byte(cfg.JwtSecret)

	// 設定 token 的過期時間 (例如：24 小時)
	expirationTime := time.Now().Add(24 * time.Hour)

	// 建立聲明
	claims := &Claims{
		UserID:   userID,
		Username: username,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(expirationTime),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			Issuer:    "chatwme-backend",
		},
	}

	// 使用 HS256 簽名演算法建立一個新的 token 物件
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)

	// 使用密鑰簽署 token 並取得完整的 token 字串
	tokenString, err := token.SignedString(jwtSecret)
	if err != nil {
		return "", err
	}

	return tokenString, nil
}

// VerifyJWT 驗證 JWT 並返回聲明
func VerifyJWT(tokenString string) (*Claims, error) {
	cfg := config.LoadConfig()
	jwtSecret := []byte(cfg.JwtSecret)

	claims := &Claims{}

	token, err := jwt.ParseWithClaims(tokenString, claims, func(token *jwt.Token) (interface{}, error) {
		// 確保 token 的簽名演算法是預期的 HMAC
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		return jwtSecret, nil
	})

	if err != nil {
		return nil, err
	}

	if !token.Valid {
		return nil, fmt.Errorf("invalid token")
	}

	return claims, nil
}

// GenerateRefreshToken 生成 Refresh Token (有效期 7 天)
func GenerateRefreshToken(userID, username string) (string, error) {
	cfg := config.LoadConfig()
	jwtSecret := []byte(cfg.JwtSecret)

	// Refresh Token 的過期時間更長 (7 天)
	expirationTime := time.Now().Add(7 * 24 * time.Hour)

	// 建立聲明
	claims := &Claims{
		UserID:   userID,
		Username: username,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(expirationTime),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			Issuer:    "chatwme-backend-refresh", // 標記為 refresh token
		},
	}

	// 使用 HS256 簽名演算法建立 token
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)

	// 使用密鑰簽署 token
	tokenString, err := token.SignedString(jwtSecret)
	if err != nil {
		return "", err
	}

	return tokenString, nil
}