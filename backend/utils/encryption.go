package utils

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"io"
)

// Encrypt 使用 AES-GCM 加密純文字
func Encrypt(plaintext string, key []byte) (string, error) {
	block, err := aes.NewCipher(key)
	if err != nil {
		return "", err
	}

	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}

	// Nonce (Number used once) 是一個不重複的隨機數，對於 GCM 模式至關重要
	// 我們將它放在加密後密文的前面，解密時需要用到
	nonce := make([]byte, gcm.NonceSize())
	if _, err = io.ReadFull(rand.Reader, nonce); err != nil {
		return "", err
	}

	// Seal 函式會處理加密，並將 nonce 作為第一個參數
	// 結果會是 nonce + ciphertext + authentication tag
	ciphertextBytes := gcm.Seal(nonce, nonce, []byte(plaintext), nil)

	// 使用 Base64 編碼，以便安全地儲存或傳輸
	return base64.StdEncoding.EncodeToString(ciphertextBytes), nil
}

// Decrypt 使用 AES-GCM 解密密文
func Decrypt(ciphertext string, key []byte) (string, error) {
	// 先將 Base64 編碼的字串解碼回 byte 陣列
	data, err := base64.StdEncoding.DecodeString(ciphertext)
	if err != nil {
		return "", err
	}

	block, err := aes.NewCipher(key)
	if err != nil {
		return "", err
	}

	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}

	nonceSize := gcm.NonceSize()
	if len(data) < nonceSize {
		return "", fmt.Errorf("ciphertext too short")
	}

	// 從資料中分離 nonce 和實際的密文
	nonce, ciphertextBytes := data[:nonceSize], data[nonceSize:]

	// Open 函式會處理解密和驗證
	plaintextBytes, err := gcm.Open(nil, nonce, ciphertextBytes, nil)
	if err != nil {
		// 如果解密失敗（例如金鑰錯誤或資料被竄改），會回傳錯誤
		return "", err
	}

	return string(plaintextBytes), nil
}
