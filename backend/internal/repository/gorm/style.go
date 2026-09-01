package gormrepo

import (
	"context"
	"errors"

	"github.com/yan/ai-image-studio/backend/internal/model"
	"github.com/yan/ai-image-studio/backend/internal/repository"
	"gorm.io/gorm"
)

type StyleRepository struct{ db *gorm.DB }

func NewStyleRepository(db *gorm.DB) *StyleRepository { return &StyleRepository{db: db} }

func (r *StyleRepository) ListEnabled(ctx context.Context) ([]model.Style, error) {
	var styles []model.Style
	err := r.db.WithContext(ctx).Where("enabled = ?", true).
		Order("sort_order ASC, id ASC").Find(&styles).Error
	return styles, err
}

func (r *StyleRepository) FindEnabledByID(ctx context.Context, styleID string) (*model.Style, error) {
	var style model.Style
	err := r.db.WithContext(ctx).Where("id = ? AND enabled = ?", styleID, true).First(&style).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, repository.ErrNotFound
	}
	return &style, err
}
