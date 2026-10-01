package catalog

import (
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
