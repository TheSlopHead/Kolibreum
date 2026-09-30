package vault

import (
	"crypto/rand"
	"fmt"
	"io"

	"golang.org/x/crypto/argon2"
	"golang.org/x/crypto/chacha20poly1305"
	"golang.org/x/crypto/hkdf"
)

func generateRandomBytes(n int) ([]byte, error) {
	b := make([]byte, n)
	_, err := io.ReadFull(rand.Reader, b)
	if err != nil {
		return nil, fmt.Errorf("random byte generation error: %v", err)
	}
	return b, nil
}

func generateRandomMasterKey() ([]byte, error) {
	masterkeySize := 32
	b := make([]byte, masterkeySize)
	_, err := io.ReadFull(rand.Reader, b)
	if err != nil {
		return nil, fmt.Errorf("MasterKey generation error: %v", err)
	}
	return b, nil
}

func DefaultKDF() (KDF, error) {
	salt, err := generateRandomBytes(32)
	if err != nil {
		return KDF{}, fmt.Errorf("cannot get random bytes: %v", err)
	}
	return KDF{
		Salt:    salt,
		Time:    3,
		Memory:  64 * 1024,
		Threads: 4,
	}, nil
}

func deriveKey(password []byte, kdf KDF) []byte {
	key := argon2.IDKey(password, kdf.Salt, kdf.Time, kdf.Memory, kdf.Threads, 32)
	return key
}

func encrypt(key []byte, plaintext []byte, additionalData []byte) (nonce []byte, ciphertext []byte, err error) {
	aead, err := chacha20poly1305.NewX(key)
	if err != nil {
		return nil, nil, fmt.Errorf("cannot get chacha20 AEAD: %v", err)
	}
	nonceSize := aead.NonceSize()
	nonce, err = generateRandomBytes(nonceSize)
	if err != nil {
		return nil, nil, fmt.Errorf("generation error: %v", err)
	}

	ciphertext = aead.Seal(nil, nonce, plaintext, additionalData)
	return nonce, ciphertext, nil
}

func decrypt(key []byte, nonce []byte, ciphertext []byte, additionalData []byte) ([]byte, error) {
	aead, err := chacha20poly1305.NewX(key)
	if err != nil {
		return nil, fmt.Errorf("Cannot get chacha20 AEAD: %v", err)
	}
	plainText, err := aead.Open(nil, nonce, ciphertext, additionalData)
	if err != nil {
		return nil, fmt.Errorf("decryption error: %v", err)
	}
	return plainText, nil
}

func deriveObjectKey(masterkey []byte, vaultID string, objectID string) ([]byte, error) {
	info := []byte("mut:object" + objectID)
	salt := vaultID

	kdf := hkdf.New()
}
