package service

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/oklog/ulid/v2"
	"github.com/yan/ai-image-studio/backend/internal/model"
	imageprovider "github.com/yan/ai-image-studio/backend/internal/provider/image"
	"github.com/yan/ai-image-studio/backend/internal/provider/image/minimax"
	"github.com/yan/ai-image-studio/backend/internal/queue"
	"github.com/yan/ai-image-studio/backend/internal/repository"
)

var (
	ErrTaskNotFound        = errors.New("task: not found")
	ErrInvalidTask         = errors.New("task: invalid request")
	ErrInsufficientCredits = errors.New("task: insufficient credits")
	ErrIdempotencyConflict = errors.New("task: idempotency conflict")
	ErrTaskNotCancelable   = errors.New("task: not cancelable")
)

type TaskService struct {
	tasks  repository.TaskRepository
	queue  queue.ImageTaskQueue
	assets *AssetService
	styles repository.StyleRepository
	now    func() time.Time
}

type CreateImageTaskInput struct {
	UserID          string
	IdempotencyKey  string
	Type            string
	Prompt          string
	StyleID         *string
	SourceAssetID   *string
	ParentTaskID    *string
	AspectRatio     string
	Count           int
	Seed            *int64
	PromptOptimizer bool
	AIGCWatermark   bool
}

type TaskResult struct {
	Task   *model.ImageTask
	Images []*AssetResult
}

type TaskPage struct {
	Tasks      []*TaskResult
	NextCursor string
}

func NewTaskService(
	tasks repository.TaskRepository,
	taskQueue queue.ImageTaskQueue,
	assets *AssetService,
	styles repository.StyleRepository,
) *TaskService {
	return &TaskService{tasks: tasks, queue: taskQueue, assets: assets, styles: styles, now: time.Now}
}

func (s *TaskService) Create(ctx context.Context, input CreateImageTaskInput) (*model.ImageTask, error) {
	input.Prompt = strings.TrimSpace(input.Prompt)
	if input.Type == "" {
		input.Type = "TEXT_TO_IMAGE"
	}
	if input.UserID == "" || input.IdempotencyKey == "" || len(input.IdempotencyKey) > 255 ||
		input.Prompt == "" || utf8.RuneCountInString(input.Prompt) > 1500 ||
		input.Count < 1 || input.Count > 4 || !validAspectRatio(input.AspectRatio) ||
		(input.Type != "TEXT_TO_IMAGE" && input.Type != "CHARACTER_REFERENCE") {
		return nil, ErrInvalidTask
	}
	if input.Type == "CHARACTER_REFERENCE" && input.SourceAssetID == nil {
		return nil, ErrInvalidTask
	}
	if input.Type == "TEXT_TO_IMAGE" && input.SourceAssetID != nil {
		return nil, ErrInvalidTask
	}
	if input.SourceAssetID != nil {
		if s.assets == nil {
			return nil, ErrInvalidTask
		}
		if _, err := s.assets.Get(ctx, input.UserID, *input.SourceAssetID); err != nil {
			return nil, ErrInvalidTask
		}
	}
	effectivePrompt := input.Prompt
	if input.StyleID != nil {
		if s.styles == nil {
			return nil, ErrInvalidTask
		}
		style, err := s.styles.FindEnabledByID(ctx, *input.StyleID)
		if errors.Is(err, repository.ErrNotFound) {
			return nil, ErrInvalidTask
		}
		if err != nil {
			return nil, fmt.Errorf("load style: %w", err)
		}
		effectivePrompt += "\n\nStyle guidance: " + style.PromptTemplate
	}
	if input.Type == "CHARACTER_REFERENCE" {
		effectivePrompt += "\n\nPreserve the referenced character's identity and recognizable facial features."
	}
	if utf8.RuneCountInString(effectivePrompt) > 1500 {
		return nil, ErrInvalidTask
	}
	requestJSON, _ := json.Marshal(input)
	digest := sha256.Sum256(requestJSON)
	now := s.now().UTC()
	task := &model.ImageTask{
		ID: ulid.Make().String(), UserID: input.UserID, Type: input.Type,
		Status: "PENDING", Prompt: input.Prompt, Provider: "minimax",
		ProviderModel: "image-01", AspectRatio: input.AspectRatio,
		ImageCount: uint8(input.Count), Seed: input.Seed,
		PromptOptimizer: input.PromptOptimizer, AIGCWatermark: input.AIGCWatermark,
		CreditsReserved: int64(input.Count * 10), CreatedAt: now, UpdatedAt: now,
	}
	task.ParentTaskID = input.ParentTaskID
	task.EffectivePrompt = &effectivePrompt
	task.StyleID = input.StyleID
	task.SourceAssetID = input.SourceAssetID
	created, existing, err := s.tasks.CreatePending(
		ctx, task, input.IdempotencyKey, hex.EncodeToString(digest[:]),
	)
	if errors.Is(err, repository.ErrInsufficientCredits) {
		return nil, ErrInsufficientCredits
	}
	if errors.Is(err, repository.ErrIdempotencyConflict) {
		return nil, ErrIdempotencyConflict
	}
	if err != nil {
		return nil, fmt.Errorf("create image task: %w", err)
	}
	if !existing {
		if err := s.queue.Enqueue(ctx, created.ID); err != nil {
			_ = s.tasks.FailAndRefund(ctx, created.ID, "QUEUE_UNAVAILABLE", "任务队列暂时不可用")
			return nil, fmt.Errorf("enqueue image task: %w", err)
		}
	}
	return created, nil
}

func (s *TaskService) Get(ctx context.Context, userID, taskID string) (*TaskResult, error) {
	task, err := s.tasks.FindByID(ctx, userID, taskID)
	if errors.Is(err, repository.ErrNotFound) {
		return nil, ErrTaskNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("find image task: %w", err)
	}
	result := &TaskResult{Task: task}
	if task.Status == "SUCCEEDED" {
		assetIDs, err := s.tasks.ResultAssetIDs(ctx, task.ID)
		if err != nil {
			return nil, fmt.Errorf("find task assets: %w", err)
		}
		for _, assetID := range assetIDs {
			asset, err := s.assets.Get(ctx, userID, assetID)
			if err != nil {
				return nil, fmt.Errorf("load task asset: %w", err)
			}
			result.Images = append(result.Images, asset)
		}
	}
	return result, nil
}

func (s *TaskService) Cancel(ctx context.Context, userID, taskID string) error {
	err := s.tasks.CancelAndRefund(ctx, userID, taskID)
	if errors.Is(err, repository.ErrNotFound) {
		return ErrTaskNotFound
	}
	if errors.Is(err, repository.ErrTaskNotCancelable) {
		return ErrTaskNotCancelable
	}
	if err != nil {
		return fmt.Errorf("cancel image task: %w", err)
	}
	return nil
}

func (s *TaskService) Retry(
	ctx context.Context,
	userID, taskID, idempotencyKey string,
) (*model.ImageTask, error) {
	previous, err := s.tasks.FindByID(ctx, userID, taskID)
	if errors.Is(err, repository.ErrNotFound) {
		return nil, ErrTaskNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("find retry task: %w", err)
	}
	if previous.Status != "FAILED" && previous.Status != "CANCELED" {
		return nil, ErrTaskNotCancelable
	}
	return s.Create(ctx, CreateImageTaskInput{
		UserID: userID, IdempotencyKey: idempotencyKey, Type: previous.Type,
		Prompt: previous.Prompt, StyleID: previous.StyleID,
		SourceAssetID: previous.SourceAssetID, ParentTaskID: &previous.ID,
		AspectRatio: previous.AspectRatio, Count: int(previous.ImageCount),
		Seed: previous.Seed, PromptOptimizer: previous.PromptOptimizer,
		AIGCWatermark: previous.AIGCWatermark,
	})
}

func (s *TaskService) List(
	ctx context.Context,
	userID, status, cursor string,
	limit int,
) (*TaskPage, error) {
	if userID == "" || limit < 1 || limit > 50 || !validTaskStatusFilter(status) {
		return nil, ErrInvalidTask
	}
	before, beforeID, err := decodeTaskCursor(cursor)
	if err != nil {
		return nil, ErrInvalidTask
	}
	tasks, err := s.tasks.ListByUser(ctx, userID, status, before, beforeID, limit+1)
	if err != nil {
		return nil, fmt.Errorf("list image tasks: %w", err)
	}
	page := &TaskPage{}
	if len(tasks) > limit {
		last := tasks[limit-1]
		page.NextCursor = encodeTaskCursor(last.CreatedAt, last.ID)
		tasks = tasks[:limit]
	}
	for index := range tasks {
		task := tasks[index]
		result := &TaskResult{Task: &task}
		if task.Status == "SUCCEEDED" {
			assetIDs, err := s.tasks.ResultAssetIDs(ctx, task.ID)
			if err != nil {
				return nil, fmt.Errorf("list task assets: %w", err)
			}
			for _, assetID := range assetIDs {
				asset, err := s.assets.Get(ctx, userID, assetID)
				if err != nil {
					return nil, fmt.Errorf("load history asset: %w", err)
				}
				result.Images = append(result.Images, asset)
			}
		}
		page.Tasks = append(page.Tasks, result)
	}
	return page, nil
}

func encodeTaskCursor(createdAt time.Time, taskID string) string {
	raw := createdAt.UTC().Format(time.RFC3339Nano) + "|" + taskID
	return base64.RawURLEncoding.EncodeToString([]byte(raw))
}

func decodeTaskCursor(cursor string) (time.Time, string, error) {
	if cursor == "" {
		return time.Time{}, "", nil
	}
	raw, err := base64.RawURLEncoding.DecodeString(cursor)
	if err != nil {
		return time.Time{}, "", err
	}
	timePart, taskID, ok := strings.Cut(string(raw), "|")
	if !ok || taskID == "" {
		return time.Time{}, "", ErrInvalidTask
	}
	createdAt, err := time.Parse(time.RFC3339Nano, timePart)
	return createdAt, taskID, err
}

func validTaskStatusFilter(status string) bool {
	switch status {
	case "", "PENDING", "PROCESSING", "SUCCEEDED", "FAILED", "CANCELED":
		return true
	default:
		return false
	}
}

type ImageTaskProcessor struct {
	tasks    repository.TaskRepository
	provider imageprovider.Provider
	assets   *AssetService
}

func NewImageTaskProcessor(
	tasks repository.TaskRepository,
	provider imageprovider.Provider,
	assets *AssetService,
) *ImageTaskProcessor {
	return &ImageTaskProcessor{tasks: tasks, provider: provider, assets: assets}
}

func (p *ImageTaskProcessor) Process(ctx context.Context, taskID string) error {
	task, err := p.tasks.Claim(ctx, taskID)
	if errors.Is(err, repository.ErrNotFound) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("claim task: %w", err)
	}
	prompt := task.Prompt
	if task.EffectivePrompt != nil {
		prompt = *task.EffectivePrompt
	}
	providerRequest := imageprovider.GenerateRequest{
		Prompt: prompt, AspectRatio: task.AspectRatio, Count: int(task.ImageCount),
		Seed: task.Seed, OptimizePrompt: task.PromptOptimizer, Watermark: task.AIGCWatermark,
	}
	if task.SourceAssetID != nil {
		reference, err := p.assets.Get(ctx, task.UserID, *task.SourceAssetID)
		if err != nil {
			_ = p.tasks.FailAndRefund(ctx, task.ID, "REFERENCE_ASSET_UNAVAILABLE", safeErrorMessage(err))
			return nil
		}
		providerRequest.References = []imageprovider.ImageReference{{Type: "character", URL: reference.URL}}
	}
	generated, err := p.provider.Generate(ctx, providerRequest)
	if err != nil {
		code := "PROVIDER_UNAVAILABLE"
		if errors.Is(err, minimax.ErrContentRejected) {
			code = "CONTENT_POLICY_REJECTED"
		}
		_ = p.tasks.FailAndRefund(ctx, task.ID, code, safeErrorMessage(err))
		return nil
	}
	assetIDs := make([]string, 0, len(generated.Images))
	for _, generatedImage := range generated.Images {
		asset, err := p.assets.StoreGenerated(ctx, task.UserID, task.ID, generatedImage.Data)
		if err != nil {
			p.cleanupAssets(ctx, task.UserID, assetIDs)
			_ = p.tasks.FailAndRefund(ctx, task.ID, "RESULT_STORAGE_FAILED", safeErrorMessage(err))
			return fmt.Errorf("store generated result: %w", err)
		}
		assetIDs = append(assetIDs, asset.ID)
	}
	if err := p.tasks.Succeed(ctx, task.ID, generated.ProviderRequestID, assetIDs); err != nil {
		p.cleanupAssets(ctx, task.UserID, assetIDs)
		_ = p.tasks.FailAndRefund(ctx, task.ID, "TASK_FINALIZE_FAILED", safeErrorMessage(err))
		return fmt.Errorf("complete task: %w", err)
	}
	return nil
}

func (p *ImageTaskProcessor) cleanupAssets(ctx context.Context, userID string, assetIDs []string) {
	for _, assetID := range assetIDs {
		_ = p.assets.Delete(ctx, userID, assetID)
	}
}

func validAspectRatio(value string) bool {
	switch value {
	case "1:1", "16:9", "9:16", "4:3", "3:4", "3:2", "2:3", "21:9":
		return true
	default:
		return false
	}
}

func safeErrorMessage(err error) string {
	message := err.Error()
	if len(message) > 900 {
		return message[:900]
	}
	return message
}
