package model

import "time"

type Style struct {
	ID                  string    `gorm:"type:char(26);primaryKey"`
	Slug                string    `gorm:"size:80;uniqueIndex;not null"`
	Name                string    `gorm:"size:120;not null"`
	Description         string    `gorm:"size:500;not null"`
	CoverAssetID        *string   `gorm:"type:char(26)"`
	PromptTemplate      string    `gorm:"type:text;not null"`
	NegativePrompt      *string   `gorm:"type:text"`
	ProviderOptionsJSON *string   `gorm:"type:json"`
	SortOrder           int       `gorm:"not null"`
	Enabled             bool      `gorm:"not null"`
	CreatedAt           time.Time `gorm:"not null"`
	UpdatedAt           time.Time `gorm:"not null"`
}

func (Style) TableName() string { return "styles" }
