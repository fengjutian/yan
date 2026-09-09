package httptransport

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/yan/ai-image-studio/backend/internal/repository"
	"github.com/yan/ai-image-studio/backend/internal/service"
)

type adminHandler struct{ admin *service.AdminService }
type adminStyleRequest struct {
	Slug           string `json:"slug"`
	Name           string `json:"name"`
	Description    string `json:"description"`
	PromptTemplate string `json:"prompt_template"`
	NegativePrompt string `json:"negative_prompt"`
	SortOrder      int    `json:"sort_order"`
	Enabled        bool   `json:"enabled"`
}
type adminUserRequest struct {
	Status       string `json:"status"`
	CreditsDelta *int64 `json:"credits_delta"`
}
type adminAIModelRequest struct {
	Provider string `json:"provider"`
	BaseURL  string `json:"base_url"`
	Model    string `json:"model"`
	APIKey   string `json:"api_key"`
	Enabled  bool   `json:"enabled"`
}

func adminMiddleware(auth *service.AuthService) gin.HandlerFunc {
	return func(c *gin.Context) {
		user, err := auth.FindUser(c.Request.Context(), c.GetString(userIDContextKey))
		if err != nil || user.Role != "ADMIN" || user.Status != "ACTIVE" {
			writeError(c, http.StatusForbidden, "ADMIN_REQUIRED", "需要管理员权限")
			c.Abort()
			return
		}
		c.Next()
	}
}
func (h adminHandler) overview(c *gin.Context) {
	value, err := h.admin.Overview(c.Request.Context())
	if err != nil {
		writeAdminError(c, err)
		return
	}
	c.JSON(http.StatusOK, value)
}
func (h adminHandler) users(c *gin.Context) {
	page, size := pageParams(c)
	values, total, err := h.admin.ListUsers(c.Request.Context(), c.Query("query"), c.Query("status"), page, size)
	if err != nil {
		writeAdminError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"items": values, "total": total, "page": page, "page_size": size})
}
func (h adminHandler) updateUser(c *gin.Context) {
	var request adminUserRequest
	if c.ShouldBindJSON(&request) != nil {
		writeAdminError(c, service.ErrAdminInvalidInput)
		return
	}
	value, err := h.admin.UpdateUser(c.Request.Context(), c.GetString(userIDContextKey), c.Param("userID"), request.Status, request.CreditsDelta)
	if err != nil {
		writeAdminError(c, err)
		return
	}
	c.JSON(http.StatusOK, value)
}
func (h adminHandler) styles(c *gin.Context) {
	values, err := h.admin.ListStyles(c.Request.Context())
	if err != nil {
		writeAdminError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"items": values})
}
func (h adminHandler) createStyle(c *gin.Context) {
	var request adminStyleRequest
	if c.ShouldBindJSON(&request) != nil {
		writeAdminError(c, service.ErrAdminInvalidInput)
		return
	}
	value, err := h.admin.CreateStyle(c.Request.Context(), c.GetString(userIDContextKey), styleInput(request))
	if err != nil {
		writeAdminError(c, err)
		return
	}
	c.JSON(http.StatusCreated, value)
}
func (h adminHandler) updateStyle(c *gin.Context) {
	var request adminStyleRequest
	if c.ShouldBindJSON(&request) != nil {
		writeAdminError(c, service.ErrAdminInvalidInput)
		return
	}
	value, err := h.admin.UpdateStyle(c.Request.Context(), c.GetString(userIDContextKey), c.Param("styleID"), styleInput(request))
	if err != nil {
		writeAdminError(c, err)
		return
	}
	c.JSON(http.StatusOK, value)
}
func (h adminHandler) deleteStyle(c *gin.Context) {
	if err := h.admin.DeleteStyle(c.Request.Context(), c.GetString(userIDContextKey), c.Param("styleID")); err != nil {
		writeAdminError(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}
func (h adminHandler) tasks(c *gin.Context) {
	page, size := pageParams(c)
	values, total, err := h.admin.ListTasks(c.Request.Context(), c.Query("status"), page, size)
	if err != nil {
		writeAdminError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"items": values, "total": total, "page": page, "page_size": size})
}
func (h adminHandler) audit(c *gin.Context) {
	page, size := pageParams(c)
	values, total, err := h.admin.ListAuditLogs(c.Request.Context(), page, size)
	if err != nil {
		writeAdminError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"items": values, "total": total, "page": page, "page_size": size})
}
func (h adminHandler) aiModel(c *gin.Context) {
	value, err := h.admin.GetAIModel(c.Request.Context())
	if err != nil { writeAdminError(c, err); return }
	c.JSON(http.StatusOK, gin.H{"provider": value.Provider, "base_url": value.BaseURL, "model": value.Model, "enabled": value.Enabled, "api_key_configured": value.APIKey != ""})
}
func (h adminHandler) updateAIModel(c *gin.Context) {
	var request adminAIModelRequest
	if c.ShouldBindJSON(&request) != nil { writeAdminError(c, service.ErrAdminInvalidInput); return }
	value, err := h.admin.UpdateAIModel(c.Request.Context(), c.GetString(userIDContextKey), service.AIModelInput{Provider: request.Provider, BaseURL: request.BaseURL, Model: request.Model, APIKey: request.APIKey, Enabled: request.Enabled})
	if err != nil { writeAdminError(c, err); return }
	c.JSON(http.StatusOK, gin.H{"provider": value.Provider, "base_url": value.BaseURL, "model": value.Model, "enabled": value.Enabled, "api_key_configured": true})
}
func styleInput(r adminStyleRequest) service.StyleInput {
	return service.StyleInput{Slug: r.Slug, Name: r.Name, Description: r.Description, PromptTemplate: r.PromptTemplate, NegativePrompt: r.NegativePrompt, SortOrder: r.SortOrder, Enabled: r.Enabled}
}
func pageParams(c *gin.Context) (int, int) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	size, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	if page < 1 {
		page = 1
	}
	if size < 1 {
		size = 20
	}
	if size > 100 {
		size = 100
	}
	return page, size
}
func writeAdminError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, service.ErrAdminInvalidInput):
		writeError(c, http.StatusBadRequest, "INVALID_REQUEST", "请检查输入内容")
	case errors.Is(err, service.ErrLastAdmin):
		writeError(c, http.StatusConflict, "CANNOT_DISABLE_SELF", "不能禁用当前管理员")
	case errors.Is(err, repository.ErrNotFound):
		writeError(c, http.StatusNotFound, "NOT_FOUND", "记录不存在")
	case errors.Is(err, repository.ErrAlreadyExists):
		writeError(c, http.StatusConflict, "SLUG_EXISTS", "标识已存在")
	case errors.Is(err, repository.ErrInsufficientCredits):
		writeError(c, http.StatusConflict, "INSUFFICIENT_CREDITS", "积分余额不能小于零")
	default:
		writeError(c, http.StatusInternalServerError, "INTERNAL_ERROR", "服务暂时不可用")
	}
}
