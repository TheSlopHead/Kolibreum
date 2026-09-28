package vault

import (
	"bytes"
	"testing"
)

func TestEncryptDescryptSuccess(t *testing.T) {
	password := []byte("super-puper-parol")
	plainText := []byte("Hello, Kovcheg!")
	VaultID := []byte("vault-uuid-12345")

	kdf, err := DefaultKDF()
	if err != nil {
		t.Fatalf("default kdf set failed: %v", err)
	}

	key := deriveKey(password, kdf)

	nonce, ciphertext, err := encrypt(key, plainText, VaultID)
	if err != nil {
		t.Fatalf("encrypt failed: %v", err)
	}

	decrypted, err := decrypt(key, nonce, ciphertext, VaultID)
	if err != nil {
		t.Fatalf("decryption failed: %v", err)
	}

	if !bytes.Equal(plainText, decrypted) {
		t.Errorf("decrypted text does not match plaintext: got %s want %s", decrypted, plainText)
	}
}

func TestDecryptWrongPassword(t *testing.T) {
	kdf, err := DefaultKDF()
	if err != nil {
		t.Fatalf("default kdf set failed: %v", err)
	}
	keyCorrect := deriveKey([]byte("correct"), kdf)
	keyWrong := deriveKey([]byte("wrong"), kdf)

	nonce, ciphertext, err := encrypt(keyCorrect, []byte("data"), []byte("vault-id"))
	if err != nil {
		t.Fatalf("encrypt failed: %v", err)
	}

	_, err = decrypt(keyWrong, nonce, ciphertext, []byte("vault-id"))
	t.Logf("err returned from decrypt: %v", err)
	if err == nil {
		t.Fatalf("expected decryption to fail with wrong password, but it succeeded")
	}

}
