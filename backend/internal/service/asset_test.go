package service

import (
	"bytes"
	"context"
	"errors"
	"image"
	"image/color"
	"image/png"
	"io"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/yan/ai-image-studio/backend/internal/model"
	"github.com/yan/ai-image-studio/backend/internal/repository"
)

func TestUploadAssetCreatesOriginalAndThumbnail(t *testing.T) {
	t.Parallel()

	repo := newMemoryAssets()
	objects := newMemoryObjectStorage()
	assets, err := NewAssetService(repo, objects, "test", 1024*1024, 1_000_000, 64, time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	data := testPNG(t, 120, 80)

	result, err := assets.Upload(context.Background(), UploadAssetInput{
		UserID: "user-1",
		Body:   bytes.NewReader(data),
		Size:   int64(len(data)),
	})
	if err != nil {
		t.Fatal(err)
	}
	if result.Asset.Width != 120 || result.Asset.Height != 80 {
		t.Fatalf("unexpected dimensions: %dx%d", result.Asset.Width, result.Asset.Height)
	}
	if result.Asset.MIMEType != "image/png" || result.Asset.SHA256 == "" {
		t.Fatalf("unexpected asset metadata: %+v", result.Asset)
	}
	if len(objects.objects) != 2 {
		t.Fatalf("expected original and thumbnail, got %d objects", len(objects.objects))
	}
	if !strings.Contains(result.URL, result.Asset.StorageKey) || result.ThumbnailURL == "" {
		t.Fatalf("missing signed URLs: %+v", result)
	}
}

func TestUploadRejectsUnsupportedFile(t *testing.T) {
	t.Parallel()

	assets, err := NewAssetService(newMemoryAssets(), newMemoryObjectStorage(), "test", 1024, 1000, 64, time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	_, err = assets.Upload(context.Background(), UploadAssetInput{
		UserID: "user-1",
		Body:   strings.NewReader("plain text"),
		Size:   10,
	})
	if !errors.Is(err, ErrUnsupportedImage) {
		t.Fatalf("expected ErrUnsupportedImage, got %v", err)
	}
}

func TestAssetOwnershipIsEnforced(t *testing.T) {
	t.Parallel()

	repo := newMemoryAssets()
	objects := newMemoryObjectStorage()
	assets, err := NewAssetService(repo, objects, "test", 1024*1024, 1_000_000, 64, time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	data := testPNG(t, 10, 10)
	created, err := assets.Upload(context.Background(), UploadAssetInput{
		UserID: "owner",
		Body:   bytes.NewReader(data),
		Size:   int64(len(data)),
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := assets.Get(context.Background(), "other-user", created.Asset.ID); !errors.Is(err, ErrAssetNotFound) {
		t.Fatalf("expected ErrAssetNotFound, got %v", err)
	}
}

func testPNG(t *testing.T, width, height int) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, width, height))
	for y := 0; y < height; y++ {
		for x := 0; x < width; x++ {
			img.Set(x, y, color.RGBA{R: 90, G: 60, B: 180, A: 255})
		}
	}
	var buffer bytes.Buffer
	if err := png.Encode(&buffer, img); err != nil {
		t.Fatal(err)
	}
	return buffer.Bytes()
}

type memoryAssets struct {
	mu     sync.Mutex
	assets map[string]*model.ImageAsset
}

func newMemoryAssets() *memoryAssets { return &memoryAssets{assets: map[string]*model.ImageAsset{}} }

func (r *memoryAssets) Create(_ context.Context, asset *model.ImageAsset) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	copy := *asset
	r.assets[asset.ID] = &copy
	return nil
}

func (r *memoryAssets) FindByID(_ context.Context, userID, assetID string) (*model.ImageAsset, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	asset, ok := r.assets[assetID]
	if !ok || asset.UserID != userID || asset.DeletedAt != nil {
		return nil, repository.ErrNotFound
	}
	copy := *asset
	return &copy, nil
}

func (r *memoryAssets) SoftDelete(_ context.Context, userID, assetID string, deletedAt time.Time) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	asset, ok := r.assets[assetID]
	if !ok || asset.UserID != userID || asset.DeletedAt != nil {
		return repository.ErrNotFound
	}
	asset.DeletedAt = &deletedAt
	return nil
}

type memoryObjectStorage struct {
	mu      sync.Mutex
	objects map[string][]byte
}

func newMemoryObjectStorage() *memoryObjectStorage {
	return &memoryObjectStorage{objects: map[string][]byte{}}
}

func (s *memoryObjectStorage) Put(_ context.Context, key, _ string, _ int64, body io.Reader) error {
	data, err := io.ReadAll(body)
	if err != nil {
		return err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.objects[key] = data
	return nil
}

func (s *memoryObjectStorage) Delete(_ context.Context, key string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.objects, key)
	return nil
}

func (s *memoryObjectStorage) PresignedGetURL(_ context.Context, key string, _ time.Duration) (string, error) {
	return "https://objects.test/" + key, nil
}
