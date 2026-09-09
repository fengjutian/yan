package gormrepo

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/go-sql-driver/mysql"
	"github.com/yan/ai-image-studio/backend/internal/model"
	"github.com/yan/ai-image-studio/backend/internal/repository"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

type AdminRepository struct{ db *gorm.DB }

func NewAdminRepository(db *gorm.DB) *AdminRepository { return &AdminRepository{db: db} }

func (r *AdminRepository) Overview(ctx context.Context) (repository.AdminOverview, error) {
	var result repository.AdminOverview
	db := r.db.WithContext(ctx)
	queries := []struct {
		model any
		where string
		value any
		out   *int64
	}{
		{&model.User{}, "deleted_at IS NULL", nil, &result.Users},
		{&model.User{}, "deleted_at IS NULL AND status = ?", "ACTIVE", &result.ActiveUsers},
		{&model.ImageTask{}, "1 = 1", nil, &result.Tasks},
		{&model.ImageTask{}, "status = ?", "SUCCEEDED", &result.CompletedTasks},
		{&model.ImageTask{}, "status = ?", "FAILED", &result.FailedTasks},
		{&model.Style{}, "1 = 1", nil, &result.Styles},
	}
	for _, q := range queries {
		query := db.Model(q.model)
		if q.value == nil {
			query = query.Where(q.where)
		} else {
			query = query.Where(q.where, q.value)
		}
		if err := query.Count(q.out).Error; err != nil {
			return result, err
		}
	}
	return result, nil
}

func (r *AdminRepository) ListUsers(ctx context.Context, search, status string, offset, limit int) ([]model.User, int64, error) {
	query := r.db.WithContext(ctx).Model(&model.User{}).Where("deleted_at IS NULL")
	if search = strings.TrimSpace(search); search != "" {
		like := "%" + search + "%"
		query = query.Where("email LIKE ? OR nickname LIKE ?", like, like)
	}
	if status != "" {
		query = query.Where("status = ?", status)
	}
	var total int64
	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}
	var users []model.User
	err := query.Order("created_at DESC, id DESC").Offset(offset).Limit(limit).Find(&users).Error
	return users, total, err
}

func (r *AdminRepository) UpdateUser(ctx context.Context, userID, status string, creditsDelta *int64, now time.Time) (*model.User, error) {
	var user model.User
	err := r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).Where("id = ? AND deleted_at IS NULL", userID).First(&user).Error; err != nil {
			return err
		}
		updates := map[string]any{"updated_at": now}
		if status != "" {
			updates["status"] = status
		}
		if creditsDelta != nil {
			if user.CreditsBalance+*creditsDelta < 0 {
				return repository.ErrInsufficientCredits
			}
			updates["credits_balance"] = gorm.Expr("credits_balance + ?", *creditsDelta)
		}
		if err := tx.Model(&user).Updates(updates).Error; err != nil {
			return err
		}
		return tx.Where("id = ?", userID).First(&user).Error
	})
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, repository.ErrNotFound
	}
	return &user, err
}

func (r *AdminRepository) ListStyles(ctx context.Context) ([]model.Style, error) {
	var styles []model.Style
	err := r.db.WithContext(ctx).Order("sort_order ASC, id ASC").Find(&styles).Error
	return styles, err
}
func (r *AdminRepository) FindStyle(ctx context.Context, id string) (*model.Style, error) {
	var style model.Style
	err := r.db.WithContext(ctx).Where("id = ?", id).First(&style).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, repository.ErrNotFound
	}
	return &style, err
}
func (r *AdminRepository) CreateStyle(ctx context.Context, style *model.Style) error {
	err := r.db.WithContext(ctx).Create(style).Error
	var mysqlErr *mysql.MySQLError
	if errors.As(err, &mysqlErr) && mysqlErr.Number == 1062 {
		return repository.ErrAlreadyExists
	}
	return err
}
func (r *AdminRepository) UpdateStyle(ctx context.Context, style *model.Style) error {
	result := r.db.WithContext(ctx).Model(&model.Style{}).Where("id = ?", style.ID).Updates(map[string]any{
		"slug": style.Slug, "name": style.Name, "description": style.Description,
		"prompt_template": style.PromptTemplate, "negative_prompt": style.NegativePrompt,
		"sort_order": style.SortOrder, "enabled": style.Enabled, "updated_at": style.UpdatedAt,
	})
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return repository.ErrNotFound
	}
	return nil
}
func (r *AdminRepository) DeleteStyle(ctx context.Context, id string) error {
	result := r.db.WithContext(ctx).Delete(&model.Style{}, "id = ?", id)
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return repository.ErrNotFound
	}
	return nil
}

func (r *AdminRepository) ListTasks(ctx context.Context, status string, offset, limit int) ([]model.ImageTask, int64, error) {
	query := r.db.WithContext(ctx).Model(&model.ImageTask{})
	if status != "" {
		query = query.Where("status = ?", status)
	}
	var total int64
	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}
	var tasks []model.ImageTask
	err := query.Order("created_at DESC, id DESC").Offset(offset).Limit(limit).Find(&tasks).Error
	return tasks, total, err
}
func (r *AdminRepository) ListAuditLogs(ctx context.Context, offset, limit int) ([]model.AdminAuditLog, int64, error) {
	query := r.db.WithContext(ctx).Model(&model.AdminAuditLog{})
	var total int64
	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}
	var logs []model.AdminAuditLog
	err := query.Order("created_at DESC, id DESC").Offset(offset).Limit(limit).Find(&logs).Error
	return logs, total, err
}
func (r *AdminRepository) CreateAuditLog(ctx context.Context, log *model.AdminAuditLog) error {
	return r.db.WithContext(ctx).Create(log).Error
}

func (r *AdminRepository) GetAIModelConfig(ctx context.Context) (*repository.AIModelConfig, error) {
	var value repository.AIModelConfig
	err := r.db.WithContext(ctx).Table("ai_model_settings").Where("id = ?", "prompt-ai").First(&value).Error
	if errors.Is(err, gorm.ErrRecordNotFound) { return nil, repository.ErrNotFound }
	return &value, err
}

func (r *AdminRepository) UpsertAIModelConfig(ctx context.Context, value *repository.AIModelConfig) error {
	row := map[string]any{
		"id": "prompt-ai", "provider": value.Provider, "base_url": value.BaseURL,
		"model": value.Model, "api_key": value.APIKey, "enabled": value.Enabled,
		"updated_by": value.UpdatedBy, "created_at": value.CreatedAt, "updated_at": value.UpdatedAt,
	}
	return r.db.WithContext(ctx).Table("ai_model_settings").Clauses(clause.OnConflict{
		Columns: []clause.Column{{Name: "id"}},
		DoUpdates: clause.AssignmentColumns([]string{"provider", "base_url", "model", "api_key", "enabled", "updated_by", "updated_at"}),
	}).Create(row).Error
}
