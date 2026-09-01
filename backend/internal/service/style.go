package service

import (
	"context"
	"fmt"

	"github.com/yan/ai-image-studio/backend/internal/model"
	"github.com/yan/ai-image-studio/backend/internal/repository"
)

type StyleService struct{ styles repository.StyleRepository }

func NewStyleService(styles repository.StyleRepository) *StyleService {
	return &StyleService{styles: styles}
}

func (s *StyleService) List(ctx context.Context) ([]model.Style, error) {
	styles, err := s.styles.ListEnabled(ctx)
	if err != nil {
		return nil, fmt.Errorf("list styles: %w", err)
	}
	return styles, nil
}
