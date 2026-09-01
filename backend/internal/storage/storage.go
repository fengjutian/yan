package storage

import (
	"context"
	"io"
	"time"
)

type ObjectStorage interface {
	Put(ctx context.Context, key, contentType string, size int64, body io.Reader) error
	Delete(ctx context.Context, key string) error
	PresignedGetURL(ctx context.Context, key string, ttl time.Duration) (string, error)
}
