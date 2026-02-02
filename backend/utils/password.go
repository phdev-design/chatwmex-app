package utils

import "golang.org/x/crypto/bcrypt"

// HashPassword 使用 bcrypt 來加密密碼
func HashPassword(password string) (string, error) {
	bytes, err := bcrypt.GenerateFromPassword([]byte(password), 14) // 14 是加密成本，是個不錯的預設值
	return string(bytes), err
}

// CheckPasswordHash 比較明文密碼和雜湊值是否相符
func CheckPasswordHash(password, hash string) bool {
	err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(password))
	return err == nil
}
