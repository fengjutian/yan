package repository

import (
	"context"
	"time"

	"github.com/yan/ai-image-studio/backend/internal/model"
)

type AdminOverview struct {
	Users, ActiveUsers, Tasks, CompletedTasks, FailedTasks, Styles int64
}

type AIModelConfig struct {
	Provider, BaseURL, Model, APIKey, UpdatedBy string
	Enabled                                    bool
	CreatedAt, UpdatedAt                       time.Time
}

type AdminRepository interface {
	Overview(ctx context.Context) (AdminOverview, error)
	ListUsers(ctx context.Context, query, status string, offset, limit int) ([]model.User, int64, error)
	UpdateUser(ctx context.Context, userID, status string, creditsDelta *int64, now time.Time) (*model.User, error)
	ListStyles(ctx context.Context) ([]model.Style, error)
	FindStyle(ctx context.Context, styleID string) (*model.Style, error)
	CreateStyle(ctx context.Context, style *model.Style) error
	UpdateStyle(ctx context.Context, style *model.Style) error
	DeleteStyle(ctx context.Context, styleID string) error
	ListTasks(ctx context.Context, status string, offset, limit int) ([]model.ImageTask, int64, error)
	ListAuditLogs(ctx context.Context, offset, limit int) ([]model.AdminAuditLog, int64, error)
	CreateAuditLog(ctx context.Context, log *model.AdminAuditLog) error
	GetAIModelConfig(ctx context.Context) (*AIModelConfig, error)
	UpsertAIModelConfig(ctx context.Context, config *AIModelConfig) error
}
