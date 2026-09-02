package httptransport

import (
	"context"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/yan/ai-image-studio/backend/internal/service"
)

const serviceName = "ai-image-api"
const userIDContextKey = "user_id"
const timeFormat = "2006-01-02T15:04:05.000Z07:00"

func NewRouter(
	environment string,
	startedAt time.Time,
	auth *service.AuthService,
	assets *service.AssetService,
	tasks *service.TaskService,
	styles *service.StyleService,
	maxUploadBytes int64,
	allowedOrigins []string,
	readiness func(context.Context) error,
) *gin.Engine {
	if environment == "production" {
		gin.SetMode(gin.ReleaseMode)
	}

	router := gin.New()
	router.Use(
		gin.Recovery(), requestID(), requestLogger(), securityHeaders(),
		cors(allowedOrigins), newIPRateLimiter(10, 30).middleware(),
	)

	router.GET("/health/live", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"status":  "ok",
			"service": serviceName,
			"uptime":  time.Since(startedAt).Round(time.Second).String(),
		})
	})

	router.GET("/health/ready", func(c *gin.Context) {
		if readiness != nil {
			if err := readiness(c.Request.Context()); err != nil {
				c.JSON(http.StatusServiceUnavailable, gin.H{"status": "not_ready"})
				return
			}
		}
		c.JSON(http.StatusOK, gin.H{"status": "ready"})
	})

	v1 := router.Group("/api/v1")
	v1.GET("/meta", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"service": serviceName,
			"version": "0.1.0-dev",
		})
	})
	if styles != nil {
		v1.GET("/styles", styleHandler{styles: styles}.list)
	}
	if auth != nil {
		handler := authHandler{auth: auth}
		authRoutes := v1.Group("/auth")
		authRoutes.POST("/register", handler.register)
		authRoutes.POST("/login", handler.login)
		authRoutes.POST("/refresh", handler.refresh)
		authRoutes.POST("/logout", handler.logout)
		v1.GET("/me", authMiddleware(auth), handler.me)
		if assets != nil {
			assetAPI := assetHandler{assets: assets, maxUploadBytes: maxUploadBytes}
			assetRoutes := v1.Group("/assets", authMiddleware(auth))
			assetRoutes.POST("", assetAPI.upload)
			assetRoutes.GET("/:assetID", assetAPI.get)
			assetRoutes.DELETE("/:assetID", assetAPI.delete)
		}
		if tasks != nil {
			taskAPI := taskHandler{tasks: tasks}
			taskRoutes := v1.Group("/image-tasks", authMiddleware(auth))
			taskRoutes.POST("", taskAPI.create)
			taskRoutes.GET("", taskAPI.list)
			taskRoutes.GET("/:taskID", taskAPI.get)
			taskRoutes.POST("/:taskID/cancel", taskAPI.cancel)
			taskRoutes.POST("/:taskID/retry", taskAPI.retry)
		}
	}

	return router
}

func requestID() gin.HandlerFunc {
	return func(c *gin.Context) {
		requestID := c.GetHeader("X-Request-ID")
		if requestID == "" {
			requestID = newRequestID()
		}
		c.Header("X-Request-ID", requestID)
		c.Set("request_id", requestID)
		c.Next()
	}
}

func newRequestID() string {
	return time.Now().UTC().Format("20060102T150405.000000000")
}
