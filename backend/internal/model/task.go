package model

import "time"

type ImageTask struct {
	ID                string  `gorm:"type:char(26);primaryKey"`
	UserID            string  `gorm:"type:char(26);index;not null"`
	ParentTaskID      *string `gorm:"type:char(26)"`
	Type              string  `gorm:"size:40;not null"`
	Status            string  `gorm:"size:32;index;not null"`
	Progress          uint8   `gorm:"not null"`
	Prompt            string  `gorm:"type:text;not null"`
	EffectivePrompt   *string `gorm:"type:text"`
	NegativePrompt    *string `gorm:"type:text"`
	StyleID           *string `gorm:"type:char(26)"`
	SourceAssetID     *string `gorm:"type:char(26)"`
	Provider          string  `gorm:"size:40;not null"`
	ProviderModel     string  `gorm:"size:80;not null"`
	ProviderRequestID *string `gorm:"size:255"`
	AspectRatio       string  `gorm:"size:16;not null"`
	Width             *uint
	Height            *uint
	ImageCount        uint8 `gorm:"not null"`
	Seed              *int64
	PromptOptimizer   bool      `gorm:"not null"`
	AIGCWatermark     bool      `gorm:"not null"`
	CreditsReserved   int64     `gorm:"not null"`
	AttemptCount      uint8     `gorm:"not null"`
	ErrorCode         *string   `gorm:"size:80"`
	ErrorMessage      *string   `gorm:"size:1000"`
	CreatedAt         time.Time `gorm:"not null"`
	StartedAt         *time.Time
	CompletedAt       *time.Time
	UpdatedAt         time.Time `gorm:"not null"`
}

func (ImageTask) TableName() string { return "image_tasks" }

type CreditLedger struct {
	ID             string    `gorm:"type:char(26);primaryKey"`
	UserID         string    `gorm:"type:char(26);index;not null"`
	TaskID         *string   `gorm:"type:char(26)"`
	Type           string    `gorm:"size:32;not null"`
	Amount         int64     `gorm:"not null"`
	BalanceAfter   int64     `gorm:"not null"`
	IdempotencyKey string    `gorm:"size:255;uniqueIndex;not null"`
	Description    string    `gorm:"size:500;not null"`
	CreatedAt      time.Time `gorm:"not null"`
}

func (CreditLedger) TableName() string { return "credit_ledger" }

type TaskAsset struct {
	TaskID    string    `gorm:"type:char(26);primaryKey"`
	AssetID   string    `gorm:"type:char(26);primaryKey"`
	Role      string    `gorm:"size:32;primaryKey"`
	Position  uint      `gorm:"not null"`
	CreatedAt time.Time `gorm:"not null"`
}

func (TaskAsset) TableName() string { return "task_assets" }

type IdempotencyRecord struct {
	ID             string    `gorm:"type:char(26);primaryKey"`
	UserID         string    `gorm:"type:char(26);not null"`
	IdempotencyKey string    `gorm:"size:255;not null"`
	RequestHash    string    `gorm:"type:char(64);not null"`
	ResourceType   string    `gorm:"size:40;not null"`
	ResourceID     string    `gorm:"type:char(26);not null"`
	ExpiresAt      time.Time `gorm:"not null"`
	CreatedAt      time.Time `gorm:"not null"`
}

func (IdempotencyRecord) TableName() string { return "idempotency_records" }
