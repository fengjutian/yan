package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/yan/ai-image-studio/backend/internal/config"
	httptransport "github.com/yan/ai-image-studio/backend/internal/transport/http"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	cfg, err := config.Load()
	if err != nil {
		logger.Error("load configuration", "error", err)
		os.Exit(1)
	}

	server := &http.Server{
		Addr:         cfg.HTTP.Address,
		Handler:      httptransport.NewRouter(cfg.Environment, time.Now()),
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
