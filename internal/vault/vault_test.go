package vault

import (
	"os"
	"path/filepath"
	"testing"
)

func TestCreateVault(t *testing.T) {
	tmpDir := t.TempDir()
	vaulthpath := filepath.Join(tmpDir, "test_vault")
	password := []byte("kakashka-vrot123")

	v, err := CreateVault(vaulthpath, password)
	if err != nil {
		t.Fatalf("create vault failed: %v", err)
	}
	if v == nil {
		t.Fatalf("expected vault object, got nil")
	}
	if len(v.masterKey) != 32 {
		t.Fatalf("lenght of masterkey not right")
	}
	if v.isLocked != false {
		t.Fatalf("created vault is open")
	}
	if v.path != vaulthpath {
		t.Fatalf("path of vault is not right")
	}

	_, err = os.Stat(filepath.Join(vaulthpath, "vault.json"))
	if err != nil {
		t.Fatal("vault.json is not exist, but should be")
	}
	_, err = os.Stat(filepath.Join(vaulthpath, "objects"))
	if err != nil {
		t.Fatal("objects/ is not exist, but should be")
	}
	_, err = os.Stat(filepath.Join(vaulthpath, "snapshots"))
	if err != nil {
		t.Fatal("snapshots/ is not exist, but should be")
	}

	_, err = CreateVault(vaulthpath, password)
	if err == nil {
		t.Fatal("expected error when creating vault over existing one")
	}
	shortPasswordPath := filepath.Join(tmpDir, "shortpass-path")
	shortPassword := []byte("kakash")
	_, err = CreateVault(shortPasswordPath, shortPassword)
	if err == nil {
		t.Fatalf("expected error for short password")
	}
}
