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
