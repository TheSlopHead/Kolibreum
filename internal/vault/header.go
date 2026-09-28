package vault

import "uuid"

type Header struct {
	Version          int       `json:"version"`
	VaultID          uuid.UUID `json:"vault_id"`
	KDF              KDF       `json:"kdf"`
	WrappedMasterKey []byte    `json:"wrapped_master_key"`
	KeyNonce         []byte    `json:"key_nonce"`
}

type KDF struct {
	Salt    []byte `json:"salt"`
	Time    uint32 `json:"time"`
	Memory  uint32 `json:"memory"`
	Threads uint8  `json:"threads"`
}
