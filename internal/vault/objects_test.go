package vault

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
)

func TestPutObject(t *testing.T) {
	tmpDir := t.TempDir()
	vaultPath := filepath.Join(tmpDir, "vault-test")
	password := []byte("kakashka-password")

	someData := []byte("some data")

	v, err := CreateVault(vaultPath, password)
	if err != nil {
		t.Fatalf("create vault error: %v", err)
	}
	if v.isLocked {
		t.Fatalf("vault is locked, expected open")
	}
	objectID, err := v.PutObject(someData)
	if err != nil {
		t.Fatalf("Put object error: %v", err)
	}
	if len(objectID) < 2 {
		t.Fatalf("lenght of objectID less than 2")
	}

	objectFilePath := filepath.Join(vaultPath, "objects", objectID[:2], objectID)
	readedData, err := os.ReadFile(objectFilePath)
	if err != nil {
		t.Fatalf("Read file error: %v", err)
	}
	if bytes.Equal(someData, readedData) {
		t.Fatalf("readed data has origin text, expected encrypted")
	}

	gettedData, err := v.GetObject(objectID)
	if err != nil {
		t.Fatalf("Get object error: %v", err)
	}
	if !bytes.Equal(gettedData, someData) {
		t.Fatalf("data not encrypted")
	}
	v.Lock()
	if !v.isLocked {
		t.Fatalf("expected locked vault, got open!")
	}

	wrongObjectID := "55667788"
	_, err = v.GetObject(wrongObjectID)
	if err == nil {
		t.Fatalf("invalid ObjectID, but object was getted: %v", err)
	}

}
