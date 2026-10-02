// Regenerate: go run mobile/tool/go_vectors.go > mobile/test/fixtures/go-vault-v2.json
// Legacy vector: go run mobile/tool/go_vectors.go -version=1
// Independent Go primitives for the mobile v2 contract. This does not change
// internal/vault; its current snapshot AAD/version still differ from mobile v2.
package main

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"flag"
	"fmt"
	"golang.org/x/crypto/argon2"
	"golang.org/x/crypto/chacha20poly1305"
	"golang.org/x/crypto/hkdf"
	"io"
	"os"
)

func entityKey(master []byte, vaultID, context string) []byte {
	reader := hkdf.New(sha256.New, master, []byte(vaultID), []byte("mut:"+context))
	key := make([]byte, 32)
	if _, err := io.ReadFull(reader, key); err != nil {
		panic(err)
	}
	return key
}

func main() {
	version := flag.Int("version", 2, "vector format: 1 or 2")
	verify := flag.String("verify", "", "verify mobile v2 payloads from a JSON file")
	flag.Parse()
	if *verify != "" {
		verifyMobile(*verify)
		return
	}
	if *version != 1 && *version != 2 {
		panic("unsupported vector version")
	}
	salt := make([]byte, 32)
	master := make([]byte, 32)
	nonce := make([]byte, 24)
	for i := range salt {
		salt[i] = byte(i)
		master[i] = byte(31 - i)
	}
	for i := range nonce {
		nonce[i] = byte(i + 17)
	}
	vaultID := "00112233-4455-4677-8899-aabbccddeeff"
	objectID := "ffeeddcc-bbaa-4988-8766-554433221100"
	wrapping := argon2.IDKey([]byte("cross-platform password"), salt, 1, 64, 1, 32)
	wrapCipher, err := chacha20poly1305.NewX(wrapping)
	if err != nil {
		panic(err)
	}
	wrapped := wrapCipher.Seal(nil, nonce, master, []byte(vaultID))
	encode := base64.StdEncoding.EncodeToString
	vector := map[string]any{
		"vault_id": vaultID, "object_id": objectID, "salt": encode(salt), "master": encode(master),
		"nonce": encode(nonce), "password": "cross-platform password", "password_key": encode(wrapping),
		"wrapped_master": encode(wrapped),
	}
	plaintext := []byte("Private book — Привет, мир.")
	if *version == 1 {
		key := entityKey(master, vaultID, "object"+objectID)
		cipher, err := chacha20poly1305.NewX(key)
		if err != nil {
			panic(err)
		}
		payload := append(append([]byte{}, nonce...), cipher.Seal(nil, nonce, plaintext, []byte(objectID))...)
		vector["object_key"] = encode(key)
		vector["plaintext"] = encode(plaintext)
		vector["payload"] = encode(payload)
	} else {
		vector["version"] = 2
		entities := []map[string]any{}
		for _, kind := range []string{"object", "snapshot"} {
			context := kind + ":" + objectID
			key := entityKey(master, vaultID, context)
			cipher, err := chacha20poly1305.NewX(key)
			if err != nil {
				panic(err)
			}
			data := plaintext
			if kind == "snapshot" {
				data = []byte(`{"version":1,"books":{},"settings":{}}`)
			}
			payload := append(append([]byte{}, nonce...), cipher.Seal(nil, nonce, data, []byte(context))...)
			entities = append(entities, map[string]any{
				"kind": kind, "id": objectID, "key": encode(key), "aad": context,
				"hkdf_info": "mut:" + context, "plaintext": encode(data), "payload": encode(payload),
			})
		}
		vector["entities"] = entities
	}
	result, err := json.MarshalIndent(vector, "", "  ")
	if err != nil {
		panic(err)
	}
	fmt.Println(string(result))
}

func verifyMobile(path string) {
	data, err := os.ReadFile(path)
	if err != nil {
		panic(err)
	}
	var input struct {
		VaultID  string `json:"vault_id"`
		Master   []byte `json:"master"`
		Entities []struct {
			Kind      string `json:"kind"`
			ID        string `json:"id"`
			Payload   []byte `json:"payload"`
			Plaintext []byte `json:"plaintext"`
		} `json:"entities"`
	}
	if err := json.Unmarshal(data, &input); err != nil {
		panic(err)
	}
	for _, entity := range input.Entities {
		if entity.Kind != "object" && entity.Kind != "snapshot" {
			panic("invalid kind")
		}
		if len(entity.Payload) < 40 {
			panic("truncated payload")
		}
		context := entity.Kind + ":" + entity.ID
		cipher, err := chacha20poly1305.NewX(entityKey(input.Master, input.VaultID, context))
		if err != nil {
			panic(err)
		}
		plain, err := cipher.Open(nil, entity.Payload[:24], entity.Payload[24:], []byte(context))
		if err != nil {
			panic(err)
		}
		if string(plain) != string(entity.Plaintext) {
			panic("plaintext mismatch")
		}
	}
	fmt.Printf("Go authenticated %d mobile v2 payloads\n", len(input.Entities))
}
