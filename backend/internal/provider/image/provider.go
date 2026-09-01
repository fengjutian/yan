package imageprovider

import "context"

type Provider interface {
	Generate(ctx context.Context, request GenerateRequest) (*GenerateResult, error)
	Capabilities() Capabilities
}

type GenerateRequest struct {
	Prompt         string
	AspectRatio    string
	Count          int
	Seed           *int64
	OptimizePrompt bool
	Watermark      bool
	References     []ImageReference
}

type ImageReference struct {
	Type string
	URL  string
}

type GenerateResult struct {
	ProviderRequestID string
	Images            []GeneratedImage
}

type GeneratedImage struct {
	Data     []byte
	MIMEType string
}

type Capabilities struct {
	TextToImage        bool
	CharacterReference bool
	Seed               bool
	CustomSize         bool
	MaxImageCount      int
}
