package service

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/yan/ai-image-studio/backend/internal/repository"
)

type promptConfigStub struct{ value *repository.AIModelConfig }

func (s promptConfigStub) GetAIModelConfig(context.Context) (*repository.AIModelConfig, error) {
	return s.value, nil
}

func TestPromptServiceEnhance(t *testing.T) {
	t.Parallel()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/chat/completions" || r.Header.Get("Authorization") != "Bearer test-key" {
			t.Fatalf("unexpected request: %s %s", r.Method, r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"<think>reasoning</think>\n\n小猫漫步在布满环形山的月面上，远处是蓝色地球。"}}]}`))
	}))
	defer server.Close()

	result, err := NewPromptService(promptConfigStub{&repository.AIModelConfig{APIKey: "test-key", BaseURL: server.URL, Model: "test-model", Enabled: true}}).Enhance(t.Context(), "小猫在月球散步")
	if err != nil {
		t.Fatal(err)
	}
	if result != "小猫漫步在布满环形山的月面上，远处是蓝色地球。" {
		t.Fatalf("unexpected result: %q", result)
	}
}

func TestPromptServiceRejectsEmptyPrompt(t *testing.T) {
	t.Parallel()
	_, err := NewPromptService(promptConfigStub{&repository.AIModelConfig{APIKey: "key", BaseURL: "https://example.test", Model: "model", Enabled: true}}).Enhance(t.Context(), "  ")
	if err == nil {
		t.Fatal("expected invalid prompt error")
	}
}
