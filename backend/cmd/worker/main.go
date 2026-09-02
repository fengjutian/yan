package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"os"

	"github.com/hibiken/asynq"
	"github.com/yan/ai-image-studio/backend/internal/config"
	"github.com/yan/ai-image-studio/backend/internal/database"
	"github.com/yan/ai-image-studio/backend/internal/provider/image/minimax"
	"github.com/yan/ai-image-studio/backend/internal/queue"
	"github.com/yan/ai-image-studio/backend/internal/repository/gorm"
	"github.com/yan/ai-image-studio/backend/internal/service"
	objectstorage "github.com/yan/ai-image-studio/backend/internal/storage"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	slog.SetDefault(logger)
	cfg, err := config.Load()
	if err != nil {
		logger.Error("load configuration", "error", err)
		os.Exit(1)
	}
	db, err := database.OpenMySQL(cfg.DatabaseDSN, cfg.Environment)
	if err != nil {
		logger.Error("connect database", "error", err)
		os.Exit(1)
	}
	minioStorage, err := objectstorage.NewMinIOStorage(
		cfg.MinIO.Endpoint, cfg.MinIO.AccessKey, cfg.MinIO.SecretKey,
		cfg.MinIO.Bucket, cfg.MinIO.UseSSL,
	)
	if err != nil {
		logger.Error("initialize object storage", "error", err)
		os.Exit(1)
	}
	assetService, err := service.NewAssetService(
		gormrepo.NewAssetRepository(db), minioStorage, cfg.MinIO.Bucket,
		cfg.Image.MaxUploadBytes, cfg.Image.MaxPixels, cfg.Image.ThumbnailSize, cfg.Image.URLTTL,
	)
	if err != nil {
		logger.Error("initialize asset service", "error", err)
		os.Exit(1)
	}
	provider, err := minimax.New(cfg.MiniMax.APIKey, cfg.MiniMax.BaseURL, cfg.MiniMax.Model, nil)
	if err != nil {
		logger.Error("initialize minimax provider", "error", err)
		os.Exit(1)
	}
	processor := service.NewImageTaskProcessor(
		gormrepo.NewTaskRepository(db), provider, assetService,
	)

	server := asynq.NewServer(
		asynq.RedisClientOpt{Addr: cfg.RedisAddr},
		asynq.Config{
			Concurrency: 4,
			Queues:      map[string]int{"images": 1},
			ErrorHandler: asynq.ErrorHandlerFunc(func(
				ctx context.Context,
				task *asynq.Task,
				err error,
			) {
				logger.Error("image task failed", "type", task.Type(), "error", err)
			}),
		},
	)
	mux := asynq.NewServeMux()
	mux.HandleFunc(queue.ImageGenerateTaskType, func(ctx context.Context, task *asynq.Task) error {
		var payload queue.ImageTaskPayload
		if err := json.Unmarshal(task.Payload(), &payload); err != nil {
			return fmt.Errorf("decode image task payload: %w", err)
		}
		return processor.Process(ctx, payload.TaskID)
	})
	logger.Info("worker started", "environment", cfg.Environment, "redis_addr", cfg.RedisAddr)
	if err := server.Run(mux); err != nil {
		logger.Error("worker stopped", "error", err)
		os.Exit(1)
	}
}
