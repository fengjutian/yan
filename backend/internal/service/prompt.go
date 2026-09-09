package service

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/yan/ai-image-studio/backend/internal/repository"
)

var (
	ErrInvalidPrompt = errors.New("invalid prompt")
	ErrPromptService = errors.New("prompt service unavailable")
)

type PromptService struct {
	config  PromptConfigProvider
	client  *http.Client
	secrets *secretCipher
}

type PromptConfigProvider interface {
	GetAIModelConfig(context.Context) (*repository.AIModelConfig, error)
}

func NewPromptService(config PromptConfigProvider, encryptionKey ...string) *PromptService {
	key := "development-only-secret"
	if len(encryptionKey) > 0 && encryptionKey[0] != "" {
		key = encryptionKey[0]
	}
	return &PromptService{
		config:  config,
		client:  &http.Client{Timeout: 14 * time.Second},
		secrets: newSecretCipher(key),
	}
}

func (s *PromptService) Enhance(ctx context.Context, prompt string) (string, error) {
	prompt = strings.TrimSpace(prompt)
	if prompt == "" || len([]rune(prompt)) > 1500 {
		return "", ErrInvalidPrompt
	}
	if err := validateSafePrompt(prompt); err != nil {
		return "", err
	}
	config, err := s.config.GetAIModelConfig(ctx)
	if err != nil || !config.Enabled || strings.TrimSpace(config.APIKey) == "" {
		return "", fmt.Errorf("%w: model is not configured", ErrPromptService)
	}
	apiKey, err := s.secrets.decrypt(config.APIKey)
	if err != nil {
		return "", fmt.Errorf("%w: decrypt model credential", ErrPromptService)
	}
	payload := map[string]any{
		"model": config.Model,
		"messages": []map[string]string{
			{"role": "system", "name": "AI绘画提示词助手", "content": "你是专业的AI绘画提示词编辑。依据用户原意补充主体细节、环境、光线、构图、色彩和材质。不要改变主体，不要解释，不要使用标题或Markdown，只输出一段可直接用于图片生成的中文提示词，控制在80到220字。"},
			{"role": "user", "name": "用户", "content": prompt},
		},
		"temperature":           0.7,
		"max_completion_tokens": 500,
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return "", fmt.Errorf("%w: %v", ErrPromptService, err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, strings.TrimRight(config.BaseURL, "/")+"/v1/chat/completions", bytes.NewReader(body))
	if err != nil {
		return "", fmt.Errorf("%w: %v", ErrPromptService, err)
	}
	req.Header.Set("Authorization", "Bearer "+apiKey)
	req.Header.Set("Content-Type", "application/json")
	resp, err := s.client.Do(req)
	if err != nil {
		return "", fmt.Errorf("%w: %v", ErrPromptService, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		limited, _ := io.ReadAll(io.LimitReader(resp.Body, 2048))
		return "", fmt.Errorf("%w: upstream status %d: %s", ErrPromptService, resp.StatusCode, strings.TrimSpace(string(limited)))
	}
	var result struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil || len(result.Choices) == 0 {
		return "", fmt.Errorf("%w: invalid upstream response", ErrPromptService)
	}
	content := strings.TrimSpace(result.Choices[0].Message.Content)
	if end := strings.LastIndex(content, "</think>"); end >= 0 {
		content = strings.TrimSpace(content[end+len("</think>"):])
	}
	if content == "" {
		return "", fmt.Errorf("%w: empty completion", ErrPromptService)
	}
	return content, nil
}
