package catalog

import (
	"encoding/json"
	"fmt"
	"time"
	"uuid"
)

type Book struct {
	ID            uuid.UUID       `json:"id"`
	Title         string          `json:"title"`
	Author        string          `json:"author"`
	Format        string          `json:"format"`
	FileObjectID  string          `json:"fileobjectid"`
	CoverObjectID string          `json:"coverobjectid"`
	FileSize      int             `json:"filesize"`
	Position      ReadingPosition `json:"position"`
	Shelves       []string        `json:"shelves"`
}

type Snapshot struct {
	Version   int             `json:"version"`
	CreatedAt time.Time       `json:"createdat"`
	Books     map[string]Book `json:"books"`
	Shelves   []string        `json:"shelves"`
}

type ReadingPosition struct {
	Progress float64   `json:"progress"`
	Locator  string    `json:"locator"`
	UpdateAt time.Time `json:"updateat"`
}

func (s *Snapshot) ToBytes() ([]byte, error) {
	snapshotBytes, err := json.Marshal(s)
	if err != nil {
		return nil, fmt.Errorf("cannot return json encoding: %w", err)
	}
	return snapshotBytes, nil
}

func (s *Snapshot) SnapshotFromBytes(data []byte) (*Snapshot, error) {
	var snapshot Snapshot
	err := json.Unmarshal(data, &snapshot)
	if err != nil {
		return nil, fmt.Errorf("cannot unmarshall data: %w", err)
	}
	if s.Books == nil {
		s.Books = make(map[string]Book)
	}
	if s.Shelves == nil {
		s.Shelves = make([]string, 0)
	}
	return &snapshot, nil
}
