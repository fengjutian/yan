package gormrepo

import (
	"context"
	"errors"
	"time"

	"github.com/yan/ai-image-studio/backend/internal/model"
	"github.com/yan/ai-image-studio/backend/internal/repository"
	"gorm.io/gorm"
)

type AssetRepository struct{ db *gorm.DB }

func NewAssetRepository(db *gorm.DB) *AssetRepository { return &AssetRepository{db: db} }

func (r *AssetRepository) Create(ctx context.Context, asset *model.ImageAsset) error {
	return r.db.WithContext(ctx).Create(asset).Error
}

func (r *AssetRepository) FindByID(ctx context.Context, userID, assetID string) (*model.ImageAsset, error) {
	var asset model.ImageAsset
	err := r.db.WithContext(ctx).
		Where("id = ? AND user_id = ? AND deleted_at IS NULL", assetID, userID).
		First(&asset).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, repository.ErrNotFound
	}
	return &asset, err
}

func (r *AssetRepository) SoftDelete(ctx context.Context, userID, assetID string, deletedAt time.Time) error {
	result := r.db.WithContext(ctx).Model(&model.ImageAsset{}).
		Where("id = ? AND user_id = ? AND deleted_at IS NULL", assetID, userID).
		Update("deleted_at", deletedAt)
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return repository.ErrNotFound
	}
	return nil
}
