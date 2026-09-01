package config

import (
	"fmt"
	"os"
	"strconv"
	"time"
)

type Config struct {
	Environment string
	HTTP        HTTPConfig
	DatabaseDSN string
	RedisAddr   string
	MinIO       MinIOConfig
	MiniMax     MiniMaxConfig
	Auth        AuthConfig
	Image       ImageConfig
}

type HTTPConfig struct {
	Address      string
	ReadTimeout  time.Duration
	WriteTimeout time.Duration
	IdleTimeout  time.Duration
}

type MinIOConfig struct {
	Endpoint  string
	AccessKey string
	SecretKey string
	Bucket    string
	UseSSL    bool
}

type MiniMaxConfig struct {
	APIKey  string
	BaseURL string
	Model   string
}

type AuthConfig struct {
	JWTSigningKey   string
	AccessTokenTTL  time.Duration
	RefreshTokenTTL time.Duration
	InitialCredits  int64
}

type ImageConfig struct {
	MaxUploadBytes int64
	MaxPixels      int64
	ThumbnailSize  int
	URLTTL         time.Duration
}

func Load() (Config, error) {
	readTimeout, err := duration("HTTP_READ_TIMEOUT", 15*time.Second)
	if err != nil {
		return Config{}, err
	}
	writeTimeout, err := duration("HTTP_WRITE_TIMEOUT", 15*time.Second)
	if err != nil {
		return Config{}, err
	}
	idleTimeout, err := duration("HTTP_IDLE_TIMEOUT", 60*time.Second)
	if err != nil {
		return Config{}, err
	}
	accessTokenTTL, err := duration("ACCESS_TOKEN_TTL", 15*time.Minute)
	if err != nil {
		return Config{}, err
	}
	refreshTokenTTL, err := duration("REFRESH_TOKEN_TTL", 30*24*time.Hour)
	if err != nil {
		return Config{}, err
	}
	initialCredits, err := integer("INITIAL_CREDITS", 100)
	if err != nil {
		return Config{}, err
	}
	maxUploadMB, err := integer("IMAGE_MAX_UPLOAD_MB", 10)
	if err != nil {
		return Config{}, err
	}
	maxPixels, err := integer("IMAGE_MAX_PIXELS", 16777216)
	if err != nil {
		return Config{}, err
	}
	thumbnailSize, err := integer("IMAGE_THUMBNAIL_SIZE", 512)
	if err != nil {
		return Config{}, err
	}
	assetURLTTL, err := duration("ASSET_URL_TTL", 15*time.Minute)
	if err != nil {
		return Config{}, err
	}
	useSSL, err := boolean("MINIO_USE_SSL", false)
	if err != nil {
		return Config{}, err
	}

	return Config{
		Environment: value("APP_ENV", "development"),
		HTTP: HTTPConfig{
			Address:      value("HTTP_ADDRESS", ":8080"),
			ReadTimeout:  readTimeout,
			WriteTimeout: writeTimeout,
			IdleTimeout:  idleTimeout,
		},
		DatabaseDSN: value("DATABASE_DSN", "app:app@tcp(localhost:3306)/ai_image_studio?parseTime=true"),
		RedisAddr:   value("REDIS_ADDR", "localhost:6379"),
		MinIO: MinIOConfig{
			Endpoint:  value("MINIO_ENDPOINT", "localhost:9000"),
			AccessKey: os.Getenv("MINIO_ACCESS_KEY"),
			SecretKey: os.Getenv("MINIO_SECRET_KEY"),
			Bucket:    value("MINIO_BUCKET", "ai-image-studio"),
			UseSSL:    useSSL,
		},
		MiniMax: MiniMaxConfig{
			APIKey:  os.Getenv("MINIMAX_API_KEY"),
			BaseURL: value("MINIMAX_BASE_URL", "https://api.minimaxi.com"),
			Model:   value("MINIMAX_IMAGE_MODEL", "image-01"),
		},
		Auth: AuthConfig{
			JWTSigningKey:   os.Getenv("JWT_SIGNING_KEY"),
			AccessTokenTTL:  accessTokenTTL,
			RefreshTokenTTL: refreshTokenTTL,
			InitialCredits:  initialCredits,
		},
		Image: ImageConfig{
			MaxUploadBytes: maxUploadMB * 1024 * 1024,
			MaxPixels:      maxPixels,
			ThumbnailSize:  int(thumbnailSize),
			URLTTL:         assetURLTTL,
		},
	}, nil
}

func integer(key string, fallback int64) (int64, error) {
	raw := os.Getenv(key)
	if raw == "" {
		return fallback, nil
	}
	parsed, err := strconv.ParseInt(raw, 10, 64)
	if err != nil {
		return 0, fmt.Errorf("parse %s: %w", key, err)
	}
	return parsed, nil
}

func value(key, fallback string) string {
	if current := os.Getenv(key); current != "" {
		return current
	}
	return fallback
}

func duration(key string, fallback time.Duration) (time.Duration, error) {
	raw := os.Getenv(key)
	if raw == "" {
		return fallback, nil
	}
	parsed, err := time.ParseDuration(raw)
	if err != nil {
		return 0, fmt.Errorf("parse %s: %w", key, err)
	}
	return parsed, nil
}

func boolean(key string, fallback bool) (bool, error) {
	raw := os.Getenv(key)
	if raw == "" {
		return fallback, nil
	}
	parsed, err := strconv.ParseBool(raw)
	if err != nil {
		return false, fmt.Errorf("parse %s: %w", key, err)
	}
	return parsed, nil
}
