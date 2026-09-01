package httptransport

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/yan/ai-image-studio/backend/internal/model"
	"github.com/yan/ai-image-studio/backend/internal/service"
)

type styleHandler struct{ styles *service.StyleService }

type styleResponse struct {
	ID          string `json:"id"`
	Slug        string `json:"slug"`
	Name        string `json:"name"`
	Description string `json:"description"`
}

func (h styleHandler) list(c *gin.Context) {
	styles, err := h.styles.List(c.Request.Context())
	if err != nil {
		writeError(c, http.StatusInternalServerError, "INTERNAL_ERROR", "暂时无法加载风格")
		return
	}
	response := make([]styleResponse, 0, len(styles))
	for _, style := range styles {
		response = append(response, publicStyle(style))
	}
	c.JSON(http.StatusOK, gin.H{"styles": response})
}

func publicStyle(style model.Style) styleResponse {
	return styleResponse{ID: style.ID, Slug: style.Slug, Name: style.Name, Description: style.Description}
}
