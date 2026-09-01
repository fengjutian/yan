package repository

import (
	"context"

	"github.com/yan/ai-image-studio/backend/internal/model"
)

type StyleRepository interface {
	ListEnabled(ctx context.Context) ([]model.Style, error)
	FindEnabledByID(ctx context.Context, styleID string) (*model.Style, error)
}
