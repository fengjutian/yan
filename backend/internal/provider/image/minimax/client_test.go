package minimax

import (
	"encoding/base64"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	imageprovider "github.com/yan/ai-image-studio/backend/internal/provider/image"
)

func TestGenerate(t *testing.T) {
	t.Parallel()

	imageData := []byte("jpeg-data")
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if request.URL.Path != "/v1/image_generation" {
			t.Fatalf("unexpected path: %s", request.URL.Path)
		}
		if request.Header.Get("Authorization") != "Bearer test-key" {
			t.Fatal("missing authorization header")
		}
		body, _ := io.ReadAll(request.Body)
		if !strings.Contains(string(body), `"response_format":"base64"`) {
			t.Fatalf("unexpected request: %s", body)
		}
		if !strings.Contains(string(body), `"image_file":"https://example.test/reference.jpg"`) {
			t.Fatalf("missing subject reference: %s", body)
		}
		writer.Header().Set("Content-Type", "application/json")
		_, _ = writer.Write([]byte(`{"id":"provider-1","data":{"image_base64":["` +
			base64.StdEncoding.EncodeToString(imageData) +
			`"]},"base_resp":{"status_code":0,"status_msg":"success"}}`))
	}))
	defer server.Close()

	provider, err := New("test-key", server.URL, "image-01", server.Client())
	if err != nil {
		t.Fatal(err)
	}
	result, err := provider.Generate(t.Context(), imageprovider.GenerateRequest{
		Prompt: "moon cat", AspectRatio: "1:1", Count: 1,
		References: []imageprovider.ImageReference{{Type: "character", URL: "https://example.test/reference.jpg"}},
	})
	if err != nil {
		t.Fatal(err)
	}
	if result.ProviderRequestID != "provider-1" || string(result.Images[0].Data) != string(imageData) {
		t.Fatalf("unexpected result: %+v", result)
	}
}

func TestRateLimit(t *testing.T) {
	t.Parallel()
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, _ *http.Request) {
		writer.WriteHeader(http.StatusTooManyRequests)
	}))
	defer server.Close()
	provider, err := New("test-key", server.URL, "image-01", server.Client())
	if err != nil {
		t.Fatal(err)
	}
	_, err = provider.Generate(t.Context(), imageprovider.GenerateRequest{Prompt: "x", Count: 1})
	if err != ErrRateLimited {
		t.Fatalf("expected ErrRateLimited, got %v", err)
	}
}
