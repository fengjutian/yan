package httptransport

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/yan/ai-image-studio/backend/internal/service"
)

type promptHandler struct{ prompts *service.PromptService }

func (h promptHandler) enhance(c *gin.Context) {
	var request struct {
		Prompt string `json:"prompt" binding:"required"`
	}
	if err := c.ShouldBindJSON(&request); err != nil {
		writeError(c, http.StatusBadRequest, "INVALID_PROMPT", "请输入需要完善的画面描述")
		return
	}
	enhanced, err := h.prompts.Enhance(c.Request.Context(), request.Prompt)
	if err != nil {
		if errors.Is(err, service.ErrUnsafePrompt) {
			writeError(c, http.StatusBadRequest, "UNSAFE_PROMPT", "描述包含不适合生成的内容，请调整后重试")
			return
		}
		if errors.Is(err, service.ErrInvalidPrompt) {
			writeError(c, http.StatusBadRequest, "INVALID_PROMPT", "画面描述长度应为 1 到 1500 字")
			return
		}
		writeError(c, http.StatusBadGateway, "PROMPT_SERVICE_UNAVAILABLE", "AI 帮写暂时不可用，请稍后重试")
		return
	}
	c.JSON(http.StatusOK, gin.H{"prompt": enhanced})
}
