package service

import (
	"context"
	"crypto/sha256"
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
)

type TaskService struct {
	tasks  repository.TaskRepository
	queue  queue.ImageTaskQueue
	assets *AssetService
	now    func() time.Time
}

type CreateImageTaskInput struct {
	UserID          string
	IdempotencyKey  string
	Prompt          string
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

func NewTaskService(tasks repository.TaskRepository, taskQueue queue.ImageTaskQueue, assets *AssetService) *TaskService {
	return &TaskService{tasks: tasks, queue: taskQueue, assets: assets, now: time.Now}
}

func (s *TaskService) Create(ctx context.Context, input CreateImageTaskInput) (*model.ImageTask, error) {
	input.Prompt = strings.TrimSpace(input.Prompt)
	if input.UserID == "" || input.IdempotencyKey == "" || len(input.IdempotencyKey) > 255 ||
		input.Prompt == "" || utf8.RuneCountInString(input.Prompt) > 1500 ||
		input.Count < 1 || input.Count > 4 || !validAspectRatio(input.AspectRatio) {
		return nil, ErrInvalidTask
	}
	requestJSON, _ := json.Marshal(input)
	digest := sha256.Sum256(requestJSON)
	now := s.now().UTC()
	task := &model.ImageTask{
		ID: ulid.Make().String(), UserID: input.UserID, Type: "TEXT_TO_IMAGE",
		Status: "PENDING", Prompt: input.Prompt, Provider: "minimax",
		ProviderModel: "image-01", AspectRatio: input.AspectRatio,
		ImageCount: uint8(input.Count), Seed: input.Seed,
		PromptOptimizer: input.PromptOptimizer, AIGCWatermark: input.AIGCWatermark,
		CreditsReserved: int64(input.Count * 10), CreatedAt: now, UpdatedAt: now,
	}
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
	generated, err := p.provider.Generate(ctx, imageprovider.GenerateRequest{
		Prompt: task.Prompt, AspectRatio: task.AspectRatio, Count: int(task.ImageCount),
		Seed: task.Seed, OptimizePrompt: task.PromptOptimizer, Watermark: task.AIGCWatermark,
	})
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
			_ = p.tasks.FailAndRefund(ctx, task.ID, "RESULT_STORAGE_FAILED", safeErrorMessage(err))
			return fmt.Errorf("store generated result: %w", err)
		}
		assetIDs = append(assetIDs, asset.ID)
	}
	if err := p.tasks.Succeed(ctx, task.ID, generated.ProviderRequestID, assetIDs); err != nil {
		return fmt.Errorf("complete task: %w", err)
	}
	return nil
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
