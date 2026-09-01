package model

import "time"

type ImageAsset struct {
	ID              string     `gorm:"type:char(26);primaryKey"`
	UserID          string     `gorm:"type:char(26);index;not null"`
	TaskID          *string    `gorm:"type:char(26);index"`
	Kind            string     `gorm:"size:32;not null"`
	StorageProvider string     `gorm:"size:32;not null"`
	Bucket          string     `gorm:"size:255;not null"`
	StorageKey      string     `gorm:"size:1024;not null"`
	ThumbnailKey    *string    `gorm:"size:1024"`
	MIMEType        string     `gorm:"size:100;not null"`
	Width           uint       `gorm:"not null"`
	Height          uint       `gorm:"not null"`
	ByteSize        uint64     `gorm:"not null"`
	SHA256          string     `gorm:"type:char(64);not null"`
	AIGenerated     bool       `gorm:"not null"`
	CreatedAt       time.Time  `gorm:"not null"`
	DeletedAt       *time.Time `gorm:"index"`
}

func (ImageAsset) TableName() string { return "image_assets" }
