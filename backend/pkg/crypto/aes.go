package crypto

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"errors"
	"io"
)

// CryptoService defines the interface for encryption and decryption.
// In Clean Architecture, interfaces are usually defined in the domain or usecase layer,
// but for a utility package like this, a concrete implementation is often sufficient
// or the interface is defined where it's used.
// Here we provide the concrete implementation.

type AESCrypto struct {
	key []byte
}

// NewAESCrypto creates a new AES-256-GCM encryption service.
// The key must be exactly 32 bytes long for AES-256.
func NewAESCrypto(key string) (*AESCrypto, error) {
	k := []byte(key)
	if len(k) != 32 {
		return nil, errors.New("invalid key size: must be 32 bytes for AES-256")
	}
	return &AESCrypto{key: k}, nil
}

// Encrypt encrypts the plaintext using AES-256-GCM and returns a base64 encoded string.
// It generates a random nonce for each encryption.
func (c *AESCrypto) Encrypt(plaintext string) (string, error) {
	block, err := aes.NewCipher(c.key)
	if err != nil {
		return "", err
	}

	aesGCM, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}

	nonce := make([]byte, aesGCM.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return "", err
	}

	ciphertext := aesGCM.Seal(nonce, nonce, []byte(plaintext), nil)
	return base64.StdEncoding.EncodeToString(ciphertext), nil
}

// Decrypt decrypts a base64 encoded ciphertext using AES-256-GCM.
func (c *AESCrypto) Decrypt(ciphertextBase64 string) (string, error) {
	data, err := base64.StdEncoding.DecodeString(ciphertextBase64)
	if err != nil {
		return "", err
	}

	block, err := aes.NewCipher(c.key)
	if err != nil {
		return "", err
	}

	aesGCM, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}

	nonceSize := aesGCM.NonceSize()
	if len(data) < nonceSize {
		return "", errors.New("ciphertext too short")
	}

	nonce, ciphertext := data[:nonceSize], data[nonceSize:]
	plaintext, err := aesGCM.Open(nil, nonce, ciphertext, nil)
	if err != nil {
		return "", err
	}

	return string(plaintext), nil
}
