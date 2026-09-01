package httptransport

import (
	"errors"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/yan/ai-image-studio/backend/internal/service"
)

type assetHandler struct {
	assets         *service.AssetService
	maxUploadBytes int64
}

type assetResponse struct {
	ID           string `json:"id"`
	Kind         string `json:"kind"`
	URL          string `json:"url"`
	ThumbnailURL string `json:"thumbnail_url,omitempty"`
	MIMEType     string `json:"mime_type"`
	Width        uint   `json:"width"`
	Height       uint   `json:"height"`
	ByteSize     uint64 `json:"byte_size"`
	AIGenerated  bool   `json:"ai_generated"`
	CreatedAt    string `json:"created_at"`
}

func (h assetHandler) upload(c *gin.Context) {
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, h.maxUploadBytes+(1<<20))
	fileHeader, err := c.FormFile("file")
	if err != nil {
		writeError(c, http.StatusBadRequest, "INVALID_UPLOAD", "请选择要上传的图片")
		return
	}
	if fileHeader.Size > h.maxUploadBytes {
		writeError(c, http.StatusRequestEntityTooLarge, "IMAGE_TOO_LARGE", "图片文件过大")
		return
	}
	file, err := fileHeader.Open()
	if err != nil {
		writeError(c, http.StatusBadRequest, "INVALID_UPLOAD", "无法读取上传图片")
		return
	}
	defer file.Close()

	result, err := h.assets.Upload(c.Request.Context(), service.UploadAssetInput{
		UserID: c.GetString(userIDContextKey),
		Body:   file,
		Size:   fileHeader.Size,
	})
	if err != nil {
		writeAssetError(c, err)
		return
	}
	c.JSON(http.StatusCreated, publicAsset(result))
}

func (h assetHandler) get(c *gin.Context) {
	result, err := h.assets.Get(
		c.Request.Context(),
		c.GetString(userIDContextKey),
		c.Param("assetID"),
	)
	if err != nil {
		writeAssetError(c, err)
		return
	}
	c.JSON(http.StatusOK, publicAsset(result))
}

func (h assetHandler) delete(c *gin.Context) {
	err := h.assets.Delete(
		c.Request.Context(),
		c.GetString(userIDContextKey),
		c.Param("assetID"),
	)
	if err != nil {
		writeAssetError(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}

func writeAssetError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, service.ErrImageTooLarge):
		writeError(c, http.StatusRequestEntityTooLarge, "IMAGE_TOO_LARGE", "图片文件过大")
	case errors.Is(err, service.ErrUnsupportedImage):
		writeError(c, http.StatusUnsupportedMediaType, "UNSUPPORTED_IMAGE", "仅支持 JPEG、PNG 和 WebP")
	case errors.Is(err, service.ErrInvalidImage), errors.Is(err, service.ErrImageDimensions):
		writeError(c, http.StatusBadRequest, "INVALID_IMAGE", "图片内容或尺寸不符合要求")
	case errors.Is(err, service.ErrAssetNotFound):
		writeError(c, http.StatusNotFound, "ASSET_NOT_FOUND", "图片不存在")
	default:
		writeError(c, http.StatusInternalServerError, "INTERNAL_ERROR", "图片服务暂时不可用")
	}
}

func publicAsset(result *service.AssetResult) assetResponse {
	asset := result.Asset
	return assetResponse{
		ID:           asset.ID,
		Kind:         asset.Kind,
		URL:          result.URL,
		ThumbnailURL: result.ThumbnailURL,
		MIMEType:     asset.MIMEType,
		Width:        asset.Width,
		Height:       asset.Height,
		ByteSize:     asset.ByteSize,
		AIGenerated:  asset.AIGenerated,
		CreatedAt:    asset.CreatedAt.Format(time.RFC3339Nano),
	}
}
