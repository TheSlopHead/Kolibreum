package vault

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"uuid"
)

var ErrNoSnapshot = errors.New("cannot find snapshot")

func (v *Vault) SaveSnapshot(data []byte) (snapshotID string, err error) {
	if v.isLocked {
		return "", ErrVaultLocked
	}
	snapshotID = uuid.New().String()

	snapshotKey, err := deriveEntityKey(v.masterKey, v.header.VaultID.String(), "snapshot", snapshotID)
	if err != nil {
		return "", fmt.Errorf("derive snapshotKey error: %v", err)
	}
	aad := []byte("snapshot:" + snapshotID)

	nonce, ciphertext, err := encrypt(snapshotKey, data, aad)
	if err != nil {
		return "", fmt.Errorf("encryptin snapshot error: %v", err)
	}
	payload := append(nonce, ciphertext...)

	headPath := filepath.Join(v.path, "HEAD")
	tmpHeadPath := filepath.Join(v.path, "HEAD.tmp")

	dir := filepath.Join(v.path, "snapshots", snapshotID[:2])
	err = os.MkdirAll(dir, 0700)
	if err != nil {
		return "", fmt.Errorf("make directory error: %v", err)
	}

	snapshotpath := filepath.Join(dir, snapshotID)
	err = os.WriteFile(snapshotpath, payload, 0600)
	if err != nil {
		return "", fmt.Errorf("write snapshot error: %v", err)
	}

	err = os.WriteFile(tmpHeadPath, []byte(snapshotID+"\n"), 0600)
	if err != nil {
		return "", fmt.Errorf("write snapshotID into tmp file error: %v", err)
	}

	err = os.Rename(tmpHeadPath, headPath)
	if err != nil {
		return "", fmt.Errorf("atomic rename HEAD error: %v", err)
	}

	return snapshotID, nil

}

func (v *Vault) GetSnapshot(snapshotID string) ([]byte, error) {
	if len(snapshotID) < 2 {
		return nil, fmt.Errorf("lenght of snapshotID less than 2")
	}
	if v.isLocked {
		return nil, ErrVaultLocked
	}
	snapshotPath := filepath.Join(v.path, "snapshots", snapshotID[:2], snapshotID)
	payload, err := os.ReadFile(snapshotPath)
	if err != nil {
		return nil, fmt.Errorf("cannot read snapshot file: %v", err)
	}
	if len(payload) < 40 {
		return nil, fmt.Errorf("invalid length of snapshot")
	}
	nonce := payload[:24]
	ciphertext := payload[24:]

	snapshotKey, err := deriveEntityKey(v.masterKey, v.header.VaultID.String(), "snapshot", snapshotID)
	if err != nil {
		return nil, fmt.Errorf("derive key error: %v", err)
	}
	aad := []byte("snapshot:" + snapshotID)

	data, err := decrypt(snapshotKey, nonce, ciphertext, aad)
	if err != nil {
		return nil, fmt.Errorf("decryption error: %v", err)
	}

	return data, nil
}

func (v *Vault) GetLastSnapshot() ([]byte, error) {
	if v.isLocked {
		return nil, ErrVaultLocked
	}
	head, err := os.ReadFile(filepath.Join(v.path, "HEAD"))
	if err != nil {
		if os.IsNotExist(err) {
			return nil, ErrNoSnapshot
		}
		return nil, fmt.Errorf("read HEAD error: %v", err)
	}

	snapshotID := strings.TrimSpace(string(head))
	if snapshotID == "" {
		return nil, ErrNoSnapshot
	}

	return v.GetSnapshot(snapshotID)
}
