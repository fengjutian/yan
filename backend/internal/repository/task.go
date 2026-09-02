package repository

import (
	"context"
	"time"

	"github.com/yan/ai-image-studio/backend/internal/model"
)

type TaskRepository interface {
	CreatePending(
		ctx context.Context,
		task *model.ImageTask,
		idempotencyKey, requestHash string,
	) (created *model.ImageTask, existing bool, err error)
	FindByID(ctx context.Context, userID, taskID string) (*model.ImageTask, error)
	ResultAssetIDs(ctx context.Context, taskID string) ([]string, error)
	ListByUser(
		ctx context.Context,
		userID, status string,
		before time.Time,
		beforeID string,
		limit int,
	) ([]model.ImageTask, error)
	Claim(ctx context.Context, taskID string) (*model.ImageTask, error)
	Succeed(ctx context.Context, taskID, providerRequestID string, assetIDs []string) error
	FailAndRefund(ctx context.Context, taskID, errorCode, errorMessage string) error
	CancelAndRefund(ctx context.Context, userID, taskID string) error
}
