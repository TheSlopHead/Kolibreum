package vault

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"uuid"
)

type Vault struct {
	path      string
	header    Header
	masterKey []byte
	isLocked  bool
}

func CreateVault(vaulthPath string, password []byte) (*Vault, error) {
	if len(password) < 8 {
		return nil, fmt.Errorf("password len is less than 8")
	}
	if len(vaulthPath) < 1 {
		return nil, fmt.Errorf("vaulthpath is empty")
	}

	jsonPath := filepath.Join(vaulthPath, "vault.json")
	_, err := os.Stat(jsonPath)
	if err == nil {
		return nil, fmt.Errorf("vault.json exists at path: %s", vaulthPath)
	}
	if !os.IsNotExist(err) {
		return nil, fmt.Errorf("file error: %v", err)
	}

	err = os.MkdirAll(filepath.Join(vaulthPath, "objects"), 0700)
	if err != nil {
		return nil, fmt.Errorf("make directory error: %v", err)
	}
	err = os.MkdirAll(filepath.Join(vaulthPath, "snapshots"), 0700)
	if err != nil {
		return nil, fmt.Errorf("make directory error: %v", err)
	}

	vaultID := uuid.New()
	masterKey, err := generateRandomMasterKey()
	if err != nil {
		return nil, fmt.Errorf("masterKey generation failed: %v", err)
	}
	kdf, err := DefaultKDF()
	if err != nil {
		return nil, fmt.Errorf("kdf generation error: %v", err)
	}
	wrappingKey := deriveKey(password, kdf)
	keyNonce, wrappedMasterKey, err := encrypt(wrappingKey, masterKey, []byte(vaultID.String()))
	if err != nil {
		return nil, fmt.Errorf("Encryprion error: %v", err)
	}
	header := Header{
		Version:          1,
		VaultID:          vaultID,
		KDF:              kdf,
		WrappedMasterKey: wrappedMasterKey,
		KeyNonce:         keyNonce,
	}
	data, err := json.MarshalIndent(header, "", "  ")
	if err != nil {
		return nil, fmt.Errorf("marshallindent error: %v", err)
	}
	err = os.WriteFile(jsonPath, data, 0600)
	if err != nil {
		return nil, fmt.Errorf("failed to write vault.json: %v", err)
	}
	return &Vault{
		path:      vaulthPath,
		header:    header,
		masterKey: masterKey,
		isLocked:  false,
	}, nil
}
