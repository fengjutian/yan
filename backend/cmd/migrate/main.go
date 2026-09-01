package main

import (
	"log/slog"
	"os"

	"github.com/yan/ai-image-studio/backend/internal/config"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	if _, err := config.Load(); err != nil {
		logger.Error("load configuration", "error", err)
		os.Exit(1)
	}

	// The container uses ordered SQL migrations during phase 0. This command is
	// the future entry point for the migration runner added with persistence.
	logger.Info("migration command ready")
}
