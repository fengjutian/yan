package repository

import (
	"context"
	"time"

	"github.com/yan/ai-image-studio/backend/internal/model"
)

type AssetRepository interface {
	Create(ctx context.Context, asset *model.ImageAsset) error
	FindByID(ctx context.Context, userID, assetID string) (*model.ImageAsset, error)
	SoftDelete(ctx context.Context, userID, assetID string, deletedAt time.Time) error
}
