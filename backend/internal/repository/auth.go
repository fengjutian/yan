package repository

import (
	"context"
	"time"

	"github.com/yan/ai-image-studio/backend/internal/model"
)

type UserRepository interface {
	Create(ctx context.Context, user *model.User) error
	FindByEmail(ctx context.Context, email string) (*model.User, error)
	FindByID(ctx context.Context, id string) (*model.User, error)
}

type RefreshTokenRepository interface {
	Create(ctx context.Context, token *model.RefreshToken) error
	Rotate(ctx context.Context, oldHash string, replacement *model.RefreshToken, now time.Time) error
	Revoke(ctx context.Context, tokenHash string, now time.Time) error
}
