package httptransport

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/yan/ai-image-studio/backend/internal/service"
)

func TestLiveness(t *testing.T) {
	t.Parallel()

	recorder := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodGet, "/health/live", nil)
	NewRouter("test", time.Now(), nil).ServeHTTP(recorder, request)

	if recorder.Code != http.StatusOK {
		t.Fatalf("expected %d, got %d", http.StatusOK, recorder.Code)
	}
	if recorder.Header().Get("X-Request-ID") == "" {
		t.Fatal("expected X-Request-ID response header")
	}
}

func TestMeRequiresAuthentication(t *testing.T) {
	t.Parallel()

	auth, err := service.NewAuthService(
		nil,
		nil,
		"test-signing-key-with-at-least-32-bytes",
		15*time.Minute,
		24*time.Hour,
		100,
	)
	if err != nil {
		t.Fatal(err)
	}
	recorder := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodGet, "/api/v1/me", nil)
	NewRouter("test", time.Now(), auth).ServeHTTP(recorder, request)

	if recorder.Code != http.StatusUnauthorized {
		t.Fatalf("expected %d, got %d", http.StatusUnauthorized, recorder.Code)
	}
	var body struct {
		Error struct {
			Code      string `json:"code"`
			RequestID string `json:"request_id"`
		} `json:"error"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body.Error.Code != "UNAUTHENTICATED" || body.Error.RequestID == "" {
		t.Fatalf("unexpected error response: %+v", body.Error)
	}
}

func TestRegisterRejectsInvalidPayload(t *testing.T) {
	t.Parallel()

	auth, err := service.NewAuthService(
		nil,
		nil,
		"test-signing-key-with-at-least-32-bytes",
		15*time.Minute,
		24*time.Hour,
		100,
	)
	if err != nil {
		t.Fatal(err)
	}
	recorder := httptest.NewRecorder()
	request := httptest.NewRequest(
		http.MethodPost,
		"/api/v1/auth/register",
		strings.NewReader(`{"email":"missing-fields@example.com"}`),
	)
	request.Header.Set("Content-Type", "application/json")
	NewRouter("test", time.Now(), auth).ServeHTTP(recorder, request)

	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("expected %d, got %d", http.StatusBadRequest, recorder.Code)
	}
}

func TestUnknownRoute(t *testing.T) {
	t.Parallel()

	recorder := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodGet, "/missing", nil)
	NewRouter("test", time.Now(), nil).ServeHTTP(recorder, request)

	if recorder.Code != http.StatusNotFound {
		t.Fatalf("expected %d, got %d", http.StatusNotFound, recorder.Code)
	}
}
