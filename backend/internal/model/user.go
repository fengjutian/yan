package model

import "time"

type User struct {
	ID             string  `gorm:"type:char(26);primaryKey"`
	Email          string  `gorm:"size:255;uniqueIndex;not null"`
	PasswordHash   string  `gorm:"size:255;not null"`
	Nickname       string  `gorm:"size:80;not null"`
	AvatarAssetID  *string `gorm:"type:char(26)"`
	Status         string  `gorm:"size:32;not null"`
	CreditsBalance int64   `gorm:"not null"`
	CreatedAt      time.Time
	UpdatedAt      time.Time
	DeletedAt      *time.Time `gorm:"index"`
}

func (User) TableName() string { return "users" }

type RefreshToken struct {
	ID         string    `gorm:"type:char(26);primaryKey"`
	UserID     string    `gorm:"type:char(26);index;not null"`
	TokenHash  string    `gorm:"type:char(64);uniqueIndex;not null"`
	ExpiresAt  time.Time `gorm:"not null"`
	RevokedAt  *time.Time
	DeviceName string    `gorm:"size:255;not null"`
	CreatedAt  time.Time `gorm:"not null"`
}

func (RefreshToken) TableName() string { return "refresh_tokens" }
