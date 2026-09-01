package httptransport

import (
	"errors"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/yan/ai-image-studio/backend/internal/service"
)

type taskHandler struct{ tasks *service.TaskService }

type createTaskRequest struct {
	Type            string  `json:"type" binding:"required"`
	Prompt          string  `json:"prompt" binding:"required"`
	StyleID         *string `json:"style_id"`
	SourceAssetID   *string `json:"source_asset_id"`
	AspectRatio     string  `json:"aspect_ratio" binding:"required"`
	Count           int     `json:"count" binding:"required"`
	Seed            *int64  `json:"seed"`
	PromptOptimizer bool    `json:"prompt_optimizer"`
}

type taskResponse struct {
	ID              string          `json:"id"`
	Type            string          `json:"type"`
	Status          string          `json:"status"`
	Progress        uint8           `json:"progress"`
	Prompt          string          `json:"prompt"`
	AspectRatio     string          `json:"aspect_ratio"`
	Count           uint8           `json:"count"`
	CreditsReserved int64           `json:"credits_reserved"`
	ErrorCode       string          `json:"error_code,omitempty"`
	ErrorMessage    string          `json:"error_message,omitempty"`
	Images          []assetResponse `json:"images"`
	CreatedAt       string          `json:"created_at"`
	CompletedAt     string          `json:"completed_at,omitempty"`
}

func (h taskHandler) create(c *gin.Context) {
	var request createTaskRequest
	if err := c.ShouldBindJSON(&request); err != nil {
		writeError(c, http.StatusBadRequest, "INVALID_TASK", "请检查生成参数")
		return
	}
	task, err := h.tasks.Create(c.Request.Context(), service.CreateImageTaskInput{
		UserID: c.GetString(userIDContextKey), IdempotencyKey: c.GetHeader("Idempotency-Key"),
		Type: request.Type, Prompt: request.Prompt, StyleID: request.StyleID,
		SourceAssetID: request.SourceAssetID, AspectRatio: request.AspectRatio, Count: request.Count,
		Seed: request.Seed, PromptOptimizer: request.PromptOptimizer, AIGCWatermark: true,
	})
	if err != nil {
		writeTaskError(c, err)
		return
	}
	c.JSON(http.StatusAccepted, publicTask(&service.TaskResult{Task: task}))
}

func (h taskHandler) get(c *gin.Context) {
	result, err := h.tasks.Get(c.Request.Context(), c.GetString(userIDContextKey), c.Param("taskID"))
	if err != nil {
		writeTaskError(c, err)
		return
	}
	c.JSON(http.StatusOK, publicTask(result))
}

func writeTaskError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, service.ErrInvalidTask):
		writeError(c, http.StatusBadRequest, "INVALID_TASK", "请检查生成参数和幂等键")
	case errors.Is(err, service.ErrInsufficientCredits):
		writeError(c, http.StatusPaymentRequired, "INSUFFICIENT_CREDITS", "可用额度不足")
	case errors.Is(err, service.ErrIdempotencyConflict):
		writeError(c, http.StatusConflict, "IDEMPOTENCY_CONFLICT", "该幂等键已用于其他请求")
	case errors.Is(err, service.ErrTaskNotFound):
		writeError(c, http.StatusNotFound, "TASK_NOT_FOUND", "生成任务不存在")
	default:
		writeError(c, http.StatusInternalServerError, "INTERNAL_ERROR", "生成服务暂时不可用")
	}
}

func publicTask(result *service.TaskResult) taskResponse {
	task := result.Task
	response := taskResponse{
		ID: task.ID, Type: task.Type, Status: task.Status, Progress: task.Progress,
		Prompt: task.Prompt, AspectRatio: task.AspectRatio, Count: task.ImageCount,
		CreditsReserved: task.CreditsReserved, Images: make([]assetResponse, 0, len(result.Images)),
		CreatedAt: task.CreatedAt.Format(time.RFC3339Nano),
	}
	if task.ErrorCode != nil {
		response.ErrorCode = *task.ErrorCode
	}
	if task.ErrorMessage != nil {
		response.ErrorMessage = *task.ErrorMessage
	}
	if task.CompletedAt != nil {
		response.CompletedAt = task.CompletedAt.Format(time.RFC3339Nano)
	}
	for _, image := range result.Images {
		response.Images = append(response.Images, publicAsset(image))
	}
	return response
}
