package service

import (
	"context"
	"encoding/json"
	"errors"
	"regexp"
	"strings"
	"time"
	"net/url"

	"github.com/oklog/ulid/v2"
	"github.com/yan/ai-image-studio/backend/internal/model"
	"github.com/yan/ai-image-studio/backend/internal/repository"
)

var ErrAdminInvalidInput = errors.New("admin: invalid input")
var ErrLastAdmin = errors.New("admin: cannot disable current admin")

type AdminService struct {
	repository repository.AdminRepository
	now        func() time.Time
}

type StyleInput struct {
	Slug, Name, Description, PromptTemplate, NegativePrompt string
	SortOrder                                               int
	Enabled                                                 bool
}

type AIModelInput struct {
	Provider, BaseURL, Model, APIKey string
	Enabled                          bool
}

func NewAdminService(repository repository.AdminRepository) *AdminService {
	return &AdminService{repository: repository, now: time.Now}
}

func (s *AdminService) Overview(ctx context.Context) (repository.AdminOverview, error) {
	return s.repository.Overview(ctx)
}
func (s *AdminService) ListUsers(ctx context.Context, query, status string, page, pageSize int) ([]model.User, int64, error) {
	page, pageSize = normalizePage(page, pageSize)
	if status != "" && status != "ACTIVE" && status != "DISABLED" {
		return nil, 0, ErrAdminInvalidInput
	}
	return s.repository.ListUsers(ctx, query, status, (page-1)*pageSize, pageSize)
}
func (s *AdminService) UpdateUser(ctx context.Context, adminID, userID, status string, creditsDelta *int64) (*model.User, error) {
	if status != "" && status != "ACTIVE" && status != "DISABLED" {
		return nil, ErrAdminInvalidInput
	}
	if status == "DISABLED" && adminID == userID {
		return nil, ErrLastAdmin
	}
	if creditsDelta == nil && status == "" {
		return nil, ErrAdminInvalidInput
	}
	user, err := s.repository.UpdateUser(ctx, userID, status, creditsDelta, s.now().UTC())
	if err == nil {
		s.audit(ctx, adminID, "USER_UPDATE", "user", userID, map[string]any{"status": status, "credits_delta": creditsDelta})
	}
	return user, err
}
func (s *AdminService) ListStyles(ctx context.Context) ([]model.Style, error) {
	return s.repository.ListStyles(ctx)
}
func (s *AdminService) CreateStyle(ctx context.Context, adminID string, input StyleInput) (*model.Style, error) {
	if err := validateStyle(input); err != nil {
		return nil, err
	}
	now := s.now().UTC()
	style := &model.Style{ID: ulid.Make().String(), Slug: strings.TrimSpace(input.Slug), Name: strings.TrimSpace(input.Name), Description: strings.TrimSpace(input.Description), PromptTemplate: strings.TrimSpace(input.PromptTemplate), SortOrder: input.SortOrder, Enabled: input.Enabled, CreatedAt: now, UpdatedAt: now}
	if value := strings.TrimSpace(input.NegativePrompt); value != "" {
		style.NegativePrompt = &value
	}
	if err := s.repository.CreateStyle(ctx, style); err != nil {
		return nil, err
	}
	s.audit(ctx, adminID, "STYLE_CREATE", "style", style.ID, map[string]any{"slug": style.Slug})
	return style, nil
}
func (s *AdminService) UpdateStyle(ctx context.Context, adminID, id string, input StyleInput) (*model.Style, error) {
	if err := validateStyle(input); err != nil {
		return nil, err
	}
	style, err := s.repository.FindStyle(ctx, id)
	if err != nil {
		return nil, err
	}
	style.Slug, style.Name, style.Description = strings.TrimSpace(input.Slug), strings.TrimSpace(input.Name), strings.TrimSpace(input.Description)
	style.PromptTemplate, style.SortOrder, style.Enabled, style.UpdatedAt = strings.TrimSpace(input.PromptTemplate), input.SortOrder, input.Enabled, s.now().UTC()
	style.NegativePrompt = nil
	if value := strings.TrimSpace(input.NegativePrompt); value != "" {
		style.NegativePrompt = &value
	}
	if err := s.repository.UpdateStyle(ctx, style); err != nil {
		return nil, err
	}
	s.audit(ctx, adminID, "STYLE_UPDATE", "style", id, map[string]any{"slug": style.Slug})
	return style, nil
}
func (s *AdminService) DeleteStyle(ctx context.Context, adminID, id string) error {
	if err := s.repository.DeleteStyle(ctx, id); err != nil {
		return err
	}
	s.audit(ctx, adminID, "STYLE_DELETE", "style", id, nil)
	return nil
}
func (s *AdminService) ListTasks(ctx context.Context, status string, page, pageSize int) ([]model.ImageTask, int64, error) {
	page, pageSize = normalizePage(page, pageSize)
	return s.repository.ListTasks(ctx, status, (page-1)*pageSize, pageSize)
}
func (s *AdminService) ListAuditLogs(ctx context.Context, page, pageSize int) ([]model.AdminAuditLog, int64, error) {
	page, pageSize = normalizePage(page, pageSize)
	return s.repository.ListAuditLogs(ctx, (page-1)*pageSize, pageSize)
}
func (s *AdminService) GetAIModel(ctx context.Context) (*repository.AIModelConfig, error) {
	value, err := s.repository.GetAIModelConfig(ctx)
	if errors.Is(err, repository.ErrNotFound) {
		return &repository.AIModelConfig{Provider: "minimax", BaseURL: "https://api.minimaxi.com", Model: "MiniMax-M2.7"}, nil
	}
	return value, err
}
func (s *AdminService) UpdateAIModel(ctx context.Context, adminID string, input AIModelInput) (*repository.AIModelConfig, error) {
	input.Provider, input.BaseURL, input.Model, input.APIKey = strings.TrimSpace(input.Provider), strings.TrimSpace(input.BaseURL), strings.TrimSpace(input.Model), strings.TrimSpace(input.APIKey)
	parsed, err := url.ParseRequestURI(input.BaseURL)
	if err != nil || (parsed.Scheme != "http" && parsed.Scheme != "https") || input.Provider == "" || input.Model == "" {
		return nil, ErrAdminInvalidInput
	}
	existing, findErr := s.repository.GetAIModelConfig(ctx)
	if input.APIKey == "" && findErr == nil { input.APIKey = existing.APIKey }
	if input.APIKey == "" { return nil, ErrAdminInvalidInput }
	now := s.now().UTC()
	value := &repository.AIModelConfig{Provider: input.Provider, BaseURL: strings.TrimRight(input.BaseURL, "/"), Model: input.Model, APIKey: input.APIKey, Enabled: input.Enabled, UpdatedBy: adminID, CreatedAt: now, UpdatedAt: now}
	if findErr == nil { value.CreatedAt = existing.CreatedAt }
	if err := s.repository.UpsertAIModelConfig(ctx, value); err != nil { return nil, err }
	s.audit(ctx, adminID, "AI_MODEL_UPDATE", "ai_model", "prompt-ai", map[string]any{"provider": value.Provider, "base_url": value.BaseURL, "model": value.Model, "enabled": value.Enabled, "api_key_changed": strings.TrimSpace(input.APIKey) != ""})
	return value, nil
}
func (s *AdminService) audit(ctx context.Context, adminID, action, resourceType, resourceID string, details any) {
	raw, _ := json.Marshal(details)
	_ = s.repository.CreateAuditLog(ctx, &model.AdminAuditLog{ID: ulid.Make().String(), AdminUserID: adminID, Action: action, ResourceType: resourceType, ResourceID: resourceID, DetailsJSON: string(raw), CreatedAt: s.now().UTC()})
}
func normalizePage(page, size int) (int, int) {
	if page < 1 {
		page = 1
	}
	if size < 1 {
		size = 20
	}
	if size > 100 {
		size = 100
	}
	return page, size
}

var styleSlug = regexp.MustCompile(`^[a-z0-9]+(?:-[a-z0-9]+)*$`)

func validateStyle(input StyleInput) error {
	if !styleSlug.MatchString(strings.TrimSpace(input.Slug)) || strings.TrimSpace(input.Name) == "" || strings.TrimSpace(input.PromptTemplate) == "" || len([]rune(input.Name)) > 120 || len([]rune(input.Description)) > 500 || len([]rune(input.PromptTemplate)) > 1200 {
		return ErrAdminInvalidInput
	}
	return nil
}
