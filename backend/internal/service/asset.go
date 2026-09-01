package service

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"image"
	"image/jpeg"
	_ "image/png"
	"io"
	"net/http"
	"path"
	"time"

	"github.com/disintegration/imaging"
	"github.com/oklog/ulid/v2"
	"github.com/yan/ai-image-studio/backend/internal/model"
	"github.com/yan/ai-image-studio/backend/internal/repository"
	"github.com/yan/ai-image-studio/backend/internal/storage"
	_ "golang.org/x/image/webp"
)

var (
	ErrAssetNotFound    = errors.New("asset: not found")
	ErrImageTooLarge    = errors.New("asset: image too large")
	ErrUnsupportedImage = errors.New("asset: unsupported image")
	ErrInvalidImage     = errors.New("asset: invalid image")
	ErrImageDimensions  = errors.New("asset: invalid image dimensions")
)

type AssetService struct {
	assets         repository.AssetRepository
	storage        storage.ObjectStorage
	bucket         string
	maxUploadBytes int64
	maxPixels      int64
	thumbnailSize  int
	urlTTL         time.Duration
	now            func() time.Time
}

type UploadAssetInput struct {
	UserID string
	Body   io.Reader
	Size   int64
}

type AssetResult struct {
	Asset        *model.ImageAsset
	URL          string
	ThumbnailURL string
}

func NewAssetService(
	assets repository.AssetRepository,
	objectStorage storage.ObjectStorage,
	bucket string,
	maxUploadBytes, maxPixels int64,
	thumbnailSize int,
	urlTTL time.Duration,
) (*AssetService, error) {
	if maxUploadBytes <= 0 || maxPixels <= 0 || thumbnailSize <= 0 || urlTTL <= 0 {
		return nil, fmt.Errorf("invalid image service configuration")
	}
	return &AssetService{
		assets:         assets,
		storage:        objectStorage,
		bucket:         bucket,
		maxUploadBytes: maxUploadBytes,
		maxPixels:      maxPixels,
		thumbnailSize:  thumbnailSize,
		urlTTL:         urlTTL,
		now:            time.Now,
	}, nil
}

func (s *AssetService) Upload(ctx context.Context, input UploadAssetInput) (*AssetResult, error) {
	if input.UserID == "" || input.Body == nil || input.Size <= 0 {
		return nil, ErrInvalidImage
	}
	if input.Size > s.maxUploadBytes {
		return nil, ErrImageTooLarge
	}

	data, err := io.ReadAll(io.LimitReader(input.Body, s.maxUploadBytes+1))
	if err != nil {
		return nil, fmt.Errorf("read upload: %w", err)
	}
	if int64(len(data)) > s.maxUploadBytes {
		return nil, ErrImageTooLarge
	}
	mimeType := http.DetectContentType(data)
	extension, supported := imageExtension(mimeType)
	if !supported {
		return nil, ErrUnsupportedImage
	}

	configuration, _, err := image.DecodeConfig(bytes.NewReader(data))
	if err != nil {
		return nil, ErrInvalidImage
	}
	pixels := int64(configuration.Width) * int64(configuration.Height)
	if configuration.Width < 1 || configuration.Height < 1 || pixels > s.maxPixels {
		return nil, ErrImageDimensions
	}
	decoded, _, err := image.Decode(bytes.NewReader(data))
	if err != nil {
		return nil, ErrInvalidImage
	}
	thumbnail := imaging.Fit(decoded, s.thumbnailSize, s.thumbnailSize, imaging.Lanczos)
	var thumbnailData bytes.Buffer
	if err := jpeg.Encode(&thumbnailData, thumbnail, &jpeg.Options{Quality: 82}); err != nil {
		return nil, fmt.Errorf("encode thumbnail: %w", err)
	}

	now := s.now().UTC()
	assetID := ulid.Make().String()
	prefix := fmt.Sprintf("%s/%04d/%02d", input.UserID, now.Year(), int(now.Month()))
	originalKey := path.Join("original", prefix, assetID+extension)
	thumbnailKey := path.Join("thumbnail", prefix, assetID+".jpg")

	if err := s.storage.Put(ctx, originalKey, mimeType, int64(len(data)), bytes.NewReader(data)); err != nil {
		return nil, fmt.Errorf("store original: %w", err)
	}
	if err := s.storage.Put(
		ctx,
		thumbnailKey,
		"image/jpeg",
		int64(thumbnailData.Len()),
		bytes.NewReader(thumbnailData.Bytes()),
	); err != nil {
		_ = s.storage.Delete(ctx, originalKey)
		return nil, fmt.Errorf("store thumbnail: %w", err)
	}

	digest := sha256.Sum256(data)
	asset := &model.ImageAsset{
		ID:              assetID,
		UserID:          input.UserID,
		Kind:            "ORIGINAL",
		StorageProvider: "minio",
		Bucket:          s.bucket,
		StorageKey:      originalKey,
		ThumbnailKey:    &thumbnailKey,
		MIMEType:        mimeType,
		Width:           uint(configuration.Width),
		Height:          uint(configuration.Height),
		ByteSize:        uint64(len(data)),
		SHA256:          hex.EncodeToString(digest[:]),
		CreatedAt:       now,
	}
	if err := s.assets.Create(ctx, asset); err != nil {
		_ = s.storage.Delete(ctx, originalKey)
		_ = s.storage.Delete(ctx, thumbnailKey)
		return nil, fmt.Errorf("create asset: %w", err)
	}
	return s.result(ctx, asset)
}

func (s *AssetService) Get(ctx context.Context, userID, assetID string) (*AssetResult, error) {
	asset, err := s.assets.FindByID(ctx, userID, assetID)
	if errors.Is(err, repository.ErrNotFound) {
		return nil, ErrAssetNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("find asset: %w", err)
	}
	return s.result(ctx, asset)
}

func (s *AssetService) StoreGenerated(
	ctx context.Context,
	userID, taskID string,
	data []byte,
) (*model.ImageAsset, error) {
	if int64(len(data)) > s.maxUploadBytes {
		return nil, ErrImageTooLarge
	}
	mimeType := http.DetectContentType(data)
	extension, supported := imageExtension(mimeType)
	if !supported {
		return nil, ErrUnsupportedImage
	}
	configuration, _, err := image.DecodeConfig(bytes.NewReader(data))
	if err != nil {
		return nil, ErrInvalidImage
	}
	if configuration.Width < 1 || configuration.Height < 1 ||
		int64(configuration.Width)*int64(configuration.Height) > s.maxPixels {
		return nil, ErrImageDimensions
	}
	decoded, _, err := image.Decode(bytes.NewReader(data))
	if err != nil {
		return nil, ErrInvalidImage
	}
	thumbnail := imaging.Fit(decoded, s.thumbnailSize, s.thumbnailSize, imaging.Lanczos)
	var thumbnailData bytes.Buffer
	if err := jpeg.Encode(&thumbnailData, thumbnail, &jpeg.Options{Quality: 82}); err != nil {
		return nil, fmt.Errorf("encode generated thumbnail: %w", err)
	}

	now := s.now().UTC()
	assetID := ulid.Make().String()
	prefix := fmt.Sprintf("%s/%04d/%02d", userID, now.Year(), int(now.Month()))
	originalKey := path.Join("generated", prefix, assetID+extension)
	thumbnailKey := path.Join("thumbnail", prefix, assetID+".jpg")
	if err := s.storage.Put(ctx, originalKey, mimeType, int64(len(data)), bytes.NewReader(data)); err != nil {
		return nil, fmt.Errorf("store generated image: %w", err)
	}
	if err := s.storage.Put(ctx, thumbnailKey, "image/jpeg", int64(thumbnailData.Len()), bytes.NewReader(thumbnailData.Bytes())); err != nil {
		_ = s.storage.Delete(ctx, originalKey)
		return nil, fmt.Errorf("store generated thumbnail: %w", err)
	}
	digest := sha256.Sum256(data)
	asset := &model.ImageAsset{
		ID: assetID, UserID: userID, TaskID: &taskID, Kind: "GENERATED",
		StorageProvider: "minio", Bucket: s.bucket, StorageKey: originalKey,
		ThumbnailKey: &thumbnailKey, MIMEType: mimeType,
		Width: uint(configuration.Width), Height: uint(configuration.Height),
		ByteSize: uint64(len(data)), SHA256: hex.EncodeToString(digest[:]),
		AIGenerated: true, CreatedAt: now,
	}
	if err := s.assets.Create(ctx, asset); err != nil {
		_ = s.storage.Delete(ctx, originalKey)
		_ = s.storage.Delete(ctx, thumbnailKey)
		return nil, fmt.Errorf("create generated asset: %w", err)
	}
	return asset, nil
}

func (s *AssetService) Delete(ctx context.Context, userID, assetID string) error {
	asset, err := s.assets.FindByID(ctx, userID, assetID)
	if errors.Is(err, repository.ErrNotFound) {
		return ErrAssetNotFound
	}
	if err != nil {
		return fmt.Errorf("find asset: %w", err)
	}
	if err := s.assets.SoftDelete(ctx, userID, assetID, s.now().UTC()); err != nil {
		return fmt.Errorf("delete asset record: %w", err)
	}
	// Logical deletion is authoritative. Failed object cleanup is safe to retry
	// asynchronously and must not make a deleted asset visible again.
	_ = s.storage.Delete(ctx, asset.StorageKey)
	if asset.ThumbnailKey != nil {
		_ = s.storage.Delete(ctx, *asset.ThumbnailKey)
	}
	return nil
}

func (s *AssetService) result(ctx context.Context, asset *model.ImageAsset) (*AssetResult, error) {
	objectURL, err := s.storage.PresignedGetURL(ctx, asset.StorageKey, s.urlTTL)
	if err != nil {
		return nil, fmt.Errorf("create asset URL: %w", err)
	}
	result := &AssetResult{Asset: asset, URL: objectURL}
	if asset.ThumbnailKey != nil {
		result.ThumbnailURL, err = s.storage.PresignedGetURL(ctx, *asset.ThumbnailKey, s.urlTTL)
		if err != nil {
			return nil, fmt.Errorf("create thumbnail URL: %w", err)
		}
	}
	return result, nil
}

func imageExtension(mimeType string) (string, bool) {
	switch mimeType {
	case "image/jpeg":
		return ".jpg", true
	case "image/png":
		return ".png", true
	case "image/webp":
		return ".webp", true
	default:
		return "", false
	}
}
