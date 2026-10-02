package vault

import (
	"fmt"
	"os"
	"path/filepath"
	"uuid"
)

func (v *Vault) SaveSnapshot(data []byte) (snapshotID string, err error) {
	if v.isLocked {
		return "", fmt.Errorf("vault ")
	}
	snapshotID = uuid.New().String()

	snapshotKey, err := deriveEntityKey(v.masterKey, v.header.VaultID.String(), "snapshot", snapshotID)
	if err != nil {
		return "", fmt.Errorf("derive snapshotKey error: %v", err)
	}

	nonce, ciphertext, err := encrypt(snapshotKey, data, []byte(snapshotID))
	if err != nil {
		return "", fmt.Errorf("encryptin snapshot error: %v", err)
	}
	payload := append(nonce, ciphertext...)

	snapshotPath := filepath.Join(v.path, "snapshots", snapshotID)
	err = os.WriteFile(snapshotPath, payload, 0600)
	if err != nil {
		return "", fmt.Errorf("write snapshot error: %v", err)
	}

	headPath := filepath.Join(v.path, "HEAD")
	tmpHeadPath := filepath.Join(v.path, "HEAD.tmp")

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
func (v *Vault) PutSnapshots(data []byte) (snapshotID string, err error) {
	if v.isLocked {
		return "", ErrVaultLocked
	}
	snapshotID = uuid.New().String()
	snapshotKey, err := deriveEntityKey(v.masterKey, v.header.VaultID.String(), "snapshot", snapshotID)
	if err != nil {
		return "", fmt.Errorf("derive obj key error: %v", err)
	}
	aad := []byte("snapshot:" + snapshotID)
	nonce, ciphertext, err := encrypt(snapshotKey, data, aad)
	if err != nil {
		return "", fmt.Errorf("encryption failed: %v", err)
	}
	payload := append(nonce, ciphertext...)
	dir := filepath.Join(v.path, "snapshot", snapshotID[:2])
	err = os.MkdirAll(dir, 0700)
	if err != nil {
		return "", fmt.Errorf("make directory error: %v", err)
	}
	snapshotpath := filepath.Join(dir, snapshotID)
	err = os.WriteFile(snapshotpath, payload, 0600)
	if err != nil {
		return "", fmt.Errorf("make directory error: %v", err)
	}
	return snapshotID, nil
}
