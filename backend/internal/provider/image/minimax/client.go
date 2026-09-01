package minimax

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	imageprovider "github.com/yan/ai-image-studio/backend/internal/provider/image"
)

var (
	ErrRateLimited     = errors.New("minimax: rate limited")
	ErrContentRejected = errors.New("minimax: content rejected")
	ErrProviderFailure = errors.New("minimax: provider failure")
)

type Provider struct {
	apiKey  string
	baseURL string
	model   string
	client  *http.Client
}

type imageRequest struct {
	Model            string             `json:"model"`
	Prompt           string             `json:"prompt"`
	ResponseFormat   string             `json:"response_format"`
	N                int                `json:"n"`
	PromptOptimizer  bool               `json:"prompt_optimizer"`
	AspectRatio      string             `json:"aspect_ratio"`
	Seed             *int64             `json:"seed,omitempty"`
	AIGCWatermark    bool               `json:"aigc_watermark"`
	SubjectReference []subjectReference `json:"subject_reference,omitempty"`
}

type subjectReference struct {
	Type      string `json:"type"`
	ImageFile string `json:"image_file"`
}

type imageResponse struct {
	ID   string `json:"id"`
	Data struct {
		ImageBase64 []string `json:"image_base64"`
	} `json:"data"`
	Metadata struct {
		FailedCount  string `json:"failed_count"`
		SuccessCount string `json:"success_count"`
	} `json:"metadata"`
	BaseResponse struct {
		StatusCode int64  `json:"status_code"`
		StatusMsg  string `json:"status_msg"`
	} `json:"base_resp"`
}

func New(apiKey, baseURL, model string, client *http.Client) (*Provider, error) {
	if strings.TrimSpace(apiKey) == "" {
		return nil, fmt.Errorf("MINIMAX_API_KEY is required")
	}
	if client == nil {
		client = &http.Client{Timeout: 180 * time.Second}
	}
	return &Provider{
		apiKey:  apiKey,
		baseURL: strings.TrimRight(baseURL, "/"),
		model:   model,
		client:  client,
	}, nil
}

func (p *Provider) Capabilities() imageprovider.Capabilities {
	return imageprovider.Capabilities{
		TextToImage:        true,
		CharacterReference: true,
		Seed:               true,
		CustomSize:         true,
		MaxImageCount:      9,
	}
}

func (p *Provider) Generate(
	ctx context.Context,
	request imageprovider.GenerateRequest,
) (*imageprovider.GenerateResult, error) {
	providerRequest := imageRequest{
		Model:           p.model,
		Prompt:          request.Prompt,
		ResponseFormat:  "base64",
		N:               request.Count,
		PromptOptimizer: request.OptimizePrompt,
		AspectRatio:     request.AspectRatio,
		Seed:            request.Seed,
		AIGCWatermark:   request.Watermark,
	}
	for _, reference := range request.References {
		providerRequest.SubjectReference = append(providerRequest.SubjectReference, subjectReference{
			Type: reference.Type, ImageFile: reference.URL,
		})
	}
	payload, err := json.Marshal(providerRequest)
	if err != nil {
		return nil, fmt.Errorf("encode minimax request: %w", err)
	}
	httpRequest, err := http.NewRequestWithContext(
		ctx,
		http.MethodPost,
		p.baseURL+"/v1/image_generation",
		bytes.NewReader(payload),
	)
	if err != nil {
		return nil, fmt.Errorf("create minimax request: %w", err)
	}
	httpRequest.Header.Set("Authorization", "Bearer "+p.apiKey)
	httpRequest.Header.Set("Content-Type", "application/json")

	response, err := p.client.Do(httpRequest)
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrProviderFailure, err)
	}
	defer response.Body.Close()
	if response.StatusCode == http.StatusTooManyRequests {
		return nil, ErrRateLimited
	}
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		_, _ = io.Copy(io.Discard, io.LimitReader(response.Body, 4096))
		return nil, fmt.Errorf("%w: http status %d", ErrProviderFailure, response.StatusCode)
	}

	var decoded imageResponse
	decoder := json.NewDecoder(io.LimitReader(response.Body, 100<<20))
	if err := decoder.Decode(&decoded); err != nil {
		return nil, fmt.Errorf("%w: decode response: %v", ErrProviderFailure, err)
	}
	if decoded.BaseResponse.StatusCode != 0 {
		if isContentRejection(decoded.BaseResponse.StatusMsg) {
			return nil, ErrContentRejected
		}
		return nil, fmt.Errorf(
			"%w: code %d: %s",
			ErrProviderFailure,
			decoded.BaseResponse.StatusCode,
			decoded.BaseResponse.StatusMsg,
		)
	}
	if len(decoded.Data.ImageBase64) == 0 {
		return nil, fmt.Errorf("%w: response contains no images", ErrProviderFailure)
	}

	result := &imageprovider.GenerateResult{ProviderRequestID: decoded.ID}
	for _, encoded := range decoded.Data.ImageBase64 {
		data, mimeType, err := decodeImage(encoded)
		if err != nil {
			return nil, fmt.Errorf("%w: %v", ErrProviderFailure, err)
		}
		result.Images = append(result.Images, imageprovider.GeneratedImage{
			Data: data, MIMEType: mimeType,
		})
	}
	return result, nil
}

func decodeImage(encoded string) ([]byte, string, error) {
	mimeType := "image/jpeg"
	if strings.HasPrefix(encoded, "data:") {
		header, body, ok := strings.Cut(encoded, ",")
		if !ok || !strings.HasSuffix(header, ";base64") {
			return nil, "", fmt.Errorf("invalid base64 data URI")
		}
		mimeType = strings.TrimSuffix(strings.TrimPrefix(header, "data:"), ";base64")
		encoded = body
	}
	data, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil {
		return nil, "", fmt.Errorf("decode image base64: %w", err)
	}
	return data, mimeType, nil
}

func isContentRejection(message string) bool {
	lowered := strings.ToLower(message)
	return strings.Contains(lowered, "sensitive") ||
		strings.Contains(lowered, "content") ||
		strings.Contains(message, "审核") ||
		strings.Contains(message, "敏感")
}
