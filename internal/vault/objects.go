package vault

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"uuid"
)

var ErrVaultLocked = errors.New("vault is locked")

func (v *Vault) PutObject(data []byte) (objectID string, err error) {
	if v.isLocked {
		return "", ErrVaultLocked
	}
	objectID = uuid.New().String()
	objKey, err := deriveObjectKey(v.masterKey, v.header.VaultID.String(), objectID)
	if err != nil {
		return "", fmt.Errorf("derive obj key error: %v", err)
	}
	nonce, ciphertext, err := encrypt(objKey, data, []byte(objectID))
	if err != nil {
		return "", fmt.Errorf("encryption failed: %v", err)
	}
	payload := append(nonce, ciphertext...)
	dir := filepath.Join(v.path, "objects", objectID[:2])
	err = os.MkdirAll(dir, 0700)
	if err != nil {
		return "", fmt.Errorf("make directory error: %v", err)
	}
	objectpath := filepath.Join(dir, objectID)
	err = os.WriteFile(objectpath, payload, 0600)
	if err != nil {
		return "", fmt.Errorf("make directory error: %v", err)
	}
	return objectID, nil
}

func (v *Vault) GetObject(objectID string) ([]byte, error) {
	if len(objectID) < 2 {
		return nil, fmt.Errorf("lenght of objectID less than 2")
	}
	if v.isLocked {
		return nil, ErrVaultLocked
	}
	objectPath := filepath.Join(v.path, "objects", objectID[:2], objectID)
	payload, err := os.ReadFile(objectPath)
	if err != nil {
		return nil, fmt.Errorf("cannot read file: %v", err)
	}
	if len(payload) < 40 {
		return nil, fmt.Errorf("invalin lenght of object: %v", err)
	}
	nonce := payload[:24]
	ciphertext := payload[24:]

	objectKey, err := deriveObjectKey(v.masterKey, v.header.VaultID.String(), objectID)
	if err != nil {
		return nil, fmt.Errorf("derive key error: %v", err)
	}

	data, err := decrypt(objectKey, nonce, ciphertext, []byte(objectID))
	if err != nil {
		return nil, fmt.Errorf("decryption error: %v", err)
	}

	return data, nil
}
