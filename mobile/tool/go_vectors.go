// Regenerate: go run mobile/tool/go_vectors.go > mobile/test/fixtures/go-vault-v1.json
// Uses the same primitives and byte layout as internal/vault/crypto.go.
package main

import (
    "crypto/sha256"
    "encoding/base64"
    "encoding/json"
    "fmt"
    "io"
    "golang.org/x/crypto/argon2"
    "golang.org/x/crypto/chacha20poly1305"
    "golang.org/x/crypto/hkdf"
)
func main() {
    salt := make([]byte,32); master := make([]byte,32); nonce:=make([]byte,24)
    for i:=range salt {salt[i]=byte(i);master[i]=byte(31-i)}
    for i:=range nonce {nonce[i]=byte(i+17)}
    vaultID:="00112233-4455-4677-8899-aabbccddeeff"
    objectID:="ffeeddcc-bbaa-4988-8766-554433221100"
    wrapping:=argon2.IDKey([]byte("cross-platform password"),salt,1,64,1,32)
    reader:=hkdf.New(sha256.New,master,[]byte(vaultID),[]byte("mut:object"+objectID))
    key:=make([]byte,32);if _,err:=io.ReadFull(reader,key);err!=nil{panic(err)}
    cipher,err:=chacha20poly1305.NewX(key);if err!=nil{panic(err)}
    plaintext:=[]byte("Private book — Привет, мир.")
    payload:=append(append([]byte{},nonce...),cipher.Seal(nil,nonce,plaintext,[]byte(objectID))...)
    wrapCipher,err:=chacha20poly1305.NewX(wrapping);if err!=nil{panic(err)}
    wrapped:=wrapCipher.Seal(nil,nonce,master,[]byte(vaultID))
    encode:=base64.StdEncoding.EncodeToString
    vector:=map[string]any{"vault_id":vaultID,"object_id":objectID,"salt":encode(salt),"master":encode(master),
      "nonce":encode(nonce),"password":"cross-platform password","password_key":encode(wrapping),
      "object_key":encode(key),"plaintext":encode(plaintext),"payload":encode(payload),"wrapped_master":encode(wrapped)}
    result,err:=json.MarshalIndent(vector,"","  ");if err!=nil{panic(err)};fmt.Println(string(result))
}
