package httptransport

import (
	"errors"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/yan/ai-image-studio/backend/internal/model"
	"github.com/yan/ai-image-studio/backend/internal/service"
)

type authHandler struct{ auth *service.AuthService }

type registerRequest struct {
	Email      string `json:"email" binding:"required"`
	Password   string `json:"password" binding:"required"`
	Nickname   string `json:"nickname" binding:"required"`
	DeviceName string `json:"device_name"`
}

type loginRequest struct {
	Email      string `json:"email" binding:"required"`
	Password   string `json:"password" binding:"required"`
	DeviceName string `json:"device_name"`
}

type refreshRequest struct {
	RefreshToken string `json:"refresh_token" binding:"required"`
	DeviceName   string `json:"device_name"`
}

type logoutRequest struct {
	RefreshToken string `json:"refresh_token" binding:"required"`
}

type userResponse struct {
	ID             string `json:"id"`
	Email          string `json:"email"`
	Nickname       string `json:"nickname"`
	AvatarAssetID  string `json:"avatar_asset_id,omitempty"`
	CreditsBalance int64  `json:"credits_balance"`
}

type tokenResponse struct {
	AccessToken      string `json:"access_token"`
	RefreshToken     string `json:"refresh_token"`
	TokenType        string `json:"token_type"`
	AccessExpiresAt  string `json:"access_expires_at"`
	RefreshExpiresAt string `json:"refresh_expires_at"`
}

type authResponse struct {
	User   userResponse  `json:"user"`
	Tokens tokenResponse `json:"tokens"`
}

func (h authHandler) register(c *gin.Context) {
	var request registerRequest
	if err := c.ShouldBindJSON(&request); err != nil {
		writeError(c, http.StatusBadRequest, "INVALID_REQUEST", "请检查注册信息")
		return
	}
	result, err := h.auth.Register(c.Request.Context(), service.RegisterInput{
		Email:      request.Email,
		Password:   request.Password,
		Nickname:   request.Nickname,
		DeviceName: request.DeviceName,
	})
	if err != nil {
		writeAuthError(c, err)
		return
	}
	c.JSON(http.StatusCreated, authResultResponse(result))
}

func (h authHandler) login(c *gin.Context) {
	var request loginRequest
	if err := c.ShouldBindJSON(&request); err != nil {
		writeError(c, http.StatusBadRequest, "INVALID_REQUEST", "请输入邮箱和密码")
		return
	}
	result, err := h.auth.Login(c.Request.Context(), service.LoginInput{
		Email:      request.Email,
		Password:   request.Password,
		DeviceName: request.DeviceName,
	})
	if err != nil {
		writeAuthError(c, err)
		return
	}
	c.JSON(http.StatusOK, authResultResponse(result))
}

func (h authHandler) refresh(c *gin.Context) {
	var request refreshRequest
	if err := c.ShouldBindJSON(&request); err != nil {
		writeError(c, http.StatusBadRequest, "INVALID_REQUEST", "缺少刷新令牌")
		return
	}
	tokens, err := h.auth.Refresh(c.Request.Context(), request.RefreshToken, request.DeviceName)
	if err != nil {
		writeAuthError(c, err)
		return
	}
	c.JSON(http.StatusOK, tokenResultResponse(*tokens))
}

func (h authHandler) logout(c *gin.Context) {
	var request logoutRequest
	if err := c.ShouldBindJSON(&request); err != nil {
		writeError(c, http.StatusBadRequest, "INVALID_REQUEST", "缺少刷新令牌")
		return
	}
	if err := h.auth.Logout(c.Request.Context(), request.RefreshToken); err != nil {
		writeAuthError(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}

func (h authHandler) me(c *gin.Context) {
	userID := c.GetString(userIDContextKey)
	user, err := h.auth.FindUser(c.Request.Context(), userID)
	if err != nil {
		writeAuthError(c, err)
		return
	}
	c.JSON(http.StatusOK, publicUser(user))
}

func authMiddleware(auth *service.AuthService) gin.HandlerFunc {
	return func(c *gin.Context) {
		authorization := c.GetHeader("Authorization")
		scheme, token, ok := strings.Cut(authorization, " ")
		if !ok || !strings.EqualFold(scheme, "Bearer") || token == "" {
			writeError(c, http.StatusUnauthorized, "UNAUTHENTICATED", "请先登录")
			c.Abort()
			return
		}
		userID, err := auth.AuthenticateAccessToken(token)
		if err != nil {
			writeError(c, http.StatusUnauthorized, "INVALID_ACCESS_TOKEN", "登录状态已过期")
			c.Abort()
			return
		}
		c.Set(userIDContextKey, userID)
		c.Next()
	}
}

func writeAuthError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, service.ErrInvalidInput):
		writeError(c, http.StatusBadRequest, "INVALID_REQUEST", "请求参数不符合要求")
	case errors.Is(err, service.ErrEmailTaken):
		writeError(c, http.StatusConflict, "EMAIL_ALREADY_REGISTERED", "该邮箱已注册")
	case errors.Is(err, service.ErrInvalidCredentials):
		writeError(c, http.StatusUnauthorized, "INVALID_CREDENTIALS", "邮箱或密码错误")
	case errors.Is(err, service.ErrInvalidToken):
		writeError(c, http.StatusUnauthorized, "INVALID_REFRESH_TOKEN", "登录状态已失效")
	case errors.Is(err, service.ErrUserDisabled):
		writeError(c, http.StatusForbidden, "USER_DISABLED", "账号当前不可用")
	default:
		writeError(c, http.StatusInternalServerError, "INTERNAL_ERROR", "服务暂时不可用")
	}
}

func writeError(c *gin.Context, status int, code, message string) {
	c.JSON(status, gin.H{
		"error": gin.H{
			"code":       code,
			"message":    message,
			"request_id": c.GetString("request_id"),
		},
	})
}

func authResultResponse(result *service.AuthResult) authResponse {
	return authResponse{User: publicUser(result.User), Tokens: tokenResultResponse(result.Tokens)}
}

func tokenResultResponse(tokens service.TokenPair) tokenResponse {
	return tokenResponse{
		AccessToken:      tokens.AccessToken,
		RefreshToken:     tokens.RefreshToken,
		TokenType:        "Bearer",
		AccessExpiresAt:  tokens.AccessExpiresAt.Format(timeFormat),
		RefreshExpiresAt: tokens.RefreshExpiresAt.Format(timeFormat),
	}
}

func publicUser(user *model.User) userResponse {
	response := userResponse{
		ID:             user.ID,
		Email:          user.Email,
		Nickname:       user.Nickname,
		CreditsBalance: user.CreditsBalance,
	}
	if user.AvatarAssetID != nil {
		response.AvatarAssetID = *user.AvatarAssetID
	}
	return response
}
