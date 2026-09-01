package gormrepo

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/oklog/ulid/v2"
	"github.com/yan/ai-image-studio/backend/internal/model"
	"github.com/yan/ai-image-studio/backend/internal/repository"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

type TaskRepository struct{ db *gorm.DB }

func NewTaskRepository(db *gorm.DB) *TaskRepository { return &TaskRepository{db: db} }

func (r *TaskRepository) CreatePending(
	ctx context.Context,
	task *model.ImageTask,
	idempotencyKey, requestHash string,
) (*model.ImageTask, bool, error) {
	var result *model.ImageTask
	var existing bool
	err := r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var record model.IdempotencyRecord
		err := tx.Where("user_id = ? AND idempotency_key = ?", task.UserID, idempotencyKey).
			First(&record).Error
		if err == nil {
			if record.RequestHash != requestHash {
				return repository.ErrIdempotencyConflict
			}
			var prior model.ImageTask
			if err := tx.First(&prior, "id = ?", record.ResourceID).Error; err != nil {
				return err
			}
			result = &prior
			existing = true
			return nil
		}
		if !errors.Is(err, gorm.ErrRecordNotFound) {
			return err
		}

		var user model.User
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			First(&user, "id = ? AND deleted_at IS NULL", task.UserID).Error; err != nil {
			return err
		}
		if user.CreditsBalance < task.CreditsReserved {
			return repository.ErrInsufficientCredits
		}
		balance := user.CreditsBalance - task.CreditsReserved
		if err := tx.Model(&model.User{}).Where("id = ?", user.ID).
			Update("credits_balance", balance).Error; err != nil {
			return err
		}
		if err := tx.Create(task).Error; err != nil {
			return err
		}
		ledger := model.CreditLedger{
			ID:             ulid.Make().String(),
			UserID:         task.UserID,
			TaskID:         &task.ID,
			Type:           "RESERVE",
			Amount:         -task.CreditsReserved,
			BalanceAfter:   balance,
			IdempotencyKey: "reserve:" + task.ID,
			Description:    "图片生成额度预占",
			CreatedAt:      task.CreatedAt,
		}
		if err := tx.Create(&ledger).Error; err != nil {
			return err
		}
		record = model.IdempotencyRecord{
			ID:             ulid.Make().String(),
			UserID:         task.UserID,
			IdempotencyKey: idempotencyKey,
			RequestHash:    requestHash,
			ResourceType:   "IMAGE_TASK",
			ResourceID:     task.ID,
			ExpiresAt:      task.CreatedAt.Add(24 * time.Hour),
			CreatedAt:      task.CreatedAt,
		}
		if err := tx.Create(&record).Error; err != nil {
			return err
		}
		result = task
		return nil
	})
	return result, existing, err
}

func (r *TaskRepository) FindByID(ctx context.Context, userID, taskID string) (*model.ImageTask, error) {
	var task model.ImageTask
	err := r.db.WithContext(ctx).Where("id = ? AND user_id = ?", taskID, userID).First(&task).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, repository.ErrNotFound
	}
	return &task, err
}

func (r *TaskRepository) ResultAssetIDs(ctx context.Context, taskID string) ([]string, error) {
	var ids []string
	err := r.db.WithContext(ctx).Model(&model.TaskAsset{}).
		Where("task_id = ? AND role = ?", taskID, "RESULT").
		Order("position ASC").
		Pluck("asset_id", &ids).Error
	return ids, err
}

func (r *TaskRepository) Claim(ctx context.Context, taskID string) (*model.ImageTask, error) {
	now := time.Now().UTC()
	result := r.db.WithContext(ctx).Model(&model.ImageTask{}).
		Where("id = ? AND status IN ?", taskID, []string{"PENDING", "RETRYING"}).
		Updates(map[string]any{
			"status":        "PROCESSING",
			"progress":      10,
			"started_at":    now,
			"updated_at":    now,
			"attempt_count": gorm.Expr("attempt_count + 1"),
		})
	if result.Error != nil {
		return nil, result.Error
	}
	if result.RowsAffected != 1 {
		return nil, repository.ErrNotFound
	}
	var task model.ImageTask
	if err := r.db.WithContext(ctx).First(&task, "id = ?", taskID).Error; err != nil {
		return nil, err
	}
	return &task, nil
}

func (r *TaskRepository) Succeed(
	ctx context.Context,
	taskID, providerRequestID string,
	assetIDs []string,
) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		now := time.Now().UTC()
		for position, assetID := range assetIDs {
			link := model.TaskAsset{
				TaskID: taskID, AssetID: assetID, Role: "RESULT",
				Position: uint(position), CreatedAt: now,
			}
			if err := tx.Clauses(clause.OnConflict{DoNothing: true}).Create(&link).Error; err != nil {
				return err
			}
		}
		result := tx.Model(&model.ImageTask{}).
			Where("id = ? AND status = ?", taskID, "PROCESSING").
			Updates(map[string]any{
				"status":              "SUCCEEDED",
				"progress":            100,
				"provider_request_id": providerRequestID,
				"completed_at":        now,
				"updated_at":          now,
			})
		if result.Error != nil {
			return result.Error
		}
		if result.RowsAffected != 1 {
			return fmt.Errorf("complete task: %w", repository.ErrNotFound)
		}
		return nil
	})
}

func (r *TaskRepository) FailAndRefund(
	ctx context.Context,
	taskID, errorCode, errorMessage string,
) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var task model.ImageTask
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).First(&task, "id = ?", taskID).Error; err != nil {
			return err
		}
		if task.Status == "FAILED" || task.Status == "SUCCEEDED" || task.Status == "CANCELED" {
			return nil
		}
		now := time.Now().UTC()
		if err := tx.Model(&task).Updates(map[string]any{
			"status": "FAILED", "progress": 100, "error_code": errorCode,
			"error_message": errorMessage, "completed_at": now, "updated_at": now,
		}).Error; err != nil {
			return err
		}
		var user model.User
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).First(&user, "id = ?", task.UserID).Error; err != nil {
			return err
		}
		balance := user.CreditsBalance + task.CreditsReserved
		if err := tx.Model(&user).Update("credits_balance", balance).Error; err != nil {
			return err
		}
		ledger := model.CreditLedger{
			ID: ulid.Make().String(), UserID: task.UserID, TaskID: &task.ID,
			Type: "REFUND", Amount: task.CreditsReserved, BalanceAfter: balance,
			IdempotencyKey: "refund:" + task.ID, Description: "图片生成失败退款", CreatedAt: now,
		}
		return tx.Clauses(clause.OnConflict{DoNothing: true}).Create(&ledger).Error
	})
}
