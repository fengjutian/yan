package httptransport

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

const serviceName = "ai-image-api"

func NewRouter(environment string, startedAt time.Time) *gin.Engine {
	if environment == "production" {
		gin.SetMode(gin.ReleaseMode)
	}

	router := gin.New()
	router.Use(gin.Recovery(), requestID())

	router.GET("/health/live", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"status":  "ok",
			"service": serviceName,
			"uptime":  time.Since(startedAt).Round(time.Second).String(),
		})
	})

	router.GET("/health/ready", func(c *gin.Context) {
		// Dependency checks are added when the database, queue and storage
		// adapters are wired in. Until then this endpoint confirms process readiness.
		c.JSON(http.StatusOK, gin.H{"status": "ready"})
	})

	v1 := router.Group("/api/v1")
	v1.GET("/meta", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"service": serviceName,
			"version": "0.1.0-dev",
		})
	})

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
