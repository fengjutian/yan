package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/redis/go-redis/v9"
	"github.com/yan/ai-image-studio/backend/internal/config"
	"github.com/yan/ai-image-studio/backend/internal/database"
	"github.com/yan/ai-image-studio/backend/internal/queue"
	"github.com/yan/ai-image-studio/backend/internal/repository/gorm"
	"github.com/yan/ai-image-studio/backend/internal/service"
	objectstorage "github.com/yan/ai-image-studio/backend/internal/storage"
	httptransport "github.com/yan/ai-image-studio/backend/internal/transport/http"
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
	userRepository := gormrepo.NewUserRepository(db)
	refreshTokenRepository := gormrepo.NewRefreshTokenRepository(db)
	authService, err := service.NewAuthService(
		userRepository,
		refreshTokenRepository,
		cfg.Auth.JWTSigningKey,
		cfg.Auth.AccessTokenTTL,
		cfg.Auth.RefreshTokenTTL,
		cfg.Auth.InitialCredits,
	)
	if err != nil {
		logger.Error("initialize authentication", "error", err)
		os.Exit(1)
	}
	minioStorage, err := objectstorage.NewMinIOStorage(
		cfg.MinIO.Endpoint,
		cfg.MinIO.AccessKey,
		cfg.MinIO.SecretKey,
		cfg.MinIO.Bucket,
		cfg.MinIO.UseSSL,
	)
	if err != nil {
		logger.Error("initialize object storage", "error", err)
		os.Exit(1)
	}
	assetRepository := gormrepo.NewAssetRepository(db)
	assetService, err := service.NewAssetService(
		assetRepository,
		minioStorage,
		cfg.MinIO.Bucket,
		cfg.Image.MaxUploadBytes,
		cfg.Image.MaxPixels,
		cfg.Image.ThumbnailSize,
		cfg.Image.URLTTL,
	)
	if err != nil {
		logger.Error("initialize asset service", "error", err)
		os.Exit(1)
	}
	taskRepository := gormrepo.NewTaskRepository(db)
	styleRepository := gormrepo.NewStyleRepository(db)
	styleService := service.NewStyleService(styleRepository)
	imageQueue := queue.NewAsynqImageQueue(cfg.RedisAddr)
	defer imageQueue.Close()
	taskService := service.NewTaskService(taskRepository, imageQueue, assetService, styleRepository)
	redisClient := redis.NewClient(&redis.Options{Addr: cfg.RedisAddr})
	defer redisClient.Close()
	sqlDB, err := db.DB()
	if err != nil {
		logger.Error("get database pool", "error", err)
		os.Exit(1)
	}
	readiness := func(ctx context.Context) error {
		if err := sqlDB.PingContext(ctx); err != nil {
			return fmt.Errorf("mysql: %w", err)
		}
		if err := redisClient.Ping(ctx).Err(); err != nil {
			return fmt.Errorf("redis: %w", err)
		}
		if err := minioStorage.Health(ctx); err != nil {
			return fmt.Errorf("minio: %w", err)
		}
		return nil
	}

	server := &http.Server{
		Addr: cfg.HTTP.Address,
		Handler: httptransport.NewRouter(
			cfg.Environment,
			time.Now(),
			authService,
			assetService,
			taskService,
			styleService,
			cfg.Image.MaxUploadBytes,
			cfg.HTTP.AllowedOrigins,
			readiness,
		),
		ReadTimeout:  cfg.HTTP.ReadTimeout,
		WriteTimeout: cfg.HTTP.WriteTimeout,
		IdleTimeout:  cfg.HTTP.IdleTimeout,
	}

	serverErrors := make(chan error, 1)
	go func() {
		logger.Info("api started", "address", cfg.HTTP.Address, "environment", cfg.Environment)
		serverErrors <- server.ListenAndServe()
	}()

	shutdownSignal, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	select {
	case <-shutdownSignal.Done():
		logger.Info("shutdown requested")
	case err = <-serverErrors:
		if !errors.Is(err, http.ErrServerClosed) {
			logger.Error("api stopped unexpectedly", "error", err)
			os.Exit(1)
		}
		return
	}

	shutdownContext, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := server.Shutdown(shutdownContext); err != nil {
		logger.Error("graceful shutdown failed", "error", err)
		os.Exit(1)
	}
	logger.Info("api stopped")
}
