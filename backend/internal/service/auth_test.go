package service

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"

	"github.com/yan/ai-image-studio/backend/internal/model"
	"github.com/yan/ai-image-studio/backend/internal/repository"
)

const testSigningKey = "test-signing-key-with-at-least-32-bytes"

func TestRegisterAndAuthenticate(t *testing.T) {
	t.Parallel()

	users := newMemoryUsers()
	tokens := newMemoryRefreshTokens()
	auth, err := NewAuthService(users, tokens, testSigningKey, 15*time.Minute, 24*time.Hour, 100)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Date(2026, 9, 1, 8, 0, 0, 0, time.UTC)
	auth.now = func() time.Time { return now }

	result, err := auth.Register(context.Background(), RegisterInput{
		Email:      " User@Example.com ",
		Password:   "secure-password",
		Nickname:   "创作者",
		DeviceName: "test",
	})
	if err != nil {
		t.Fatal(err)
	}
	if result.User.Email != "user@example.com" {
		t.Fatalf("email was not normalized: %s", result.User.Email)
	}
	if result.User.CreditsBalance != 100 {
		t.Fatalf("expected 100 initial credits, got %d", result.User.CreditsBalance)
	}
	if result.User.PasswordHash == "secure-password" {
		t.Fatal("password was not hashed")
	}

	userID, err := auth.AuthenticateAccessToken(result.Tokens.AccessToken)
	if err != nil {
		t.Fatal(err)
	}
	if userID != result.User.ID {
		t.Fatalf("expected user %s, got %s", result.User.ID, userID)
	}
}

func TestDuplicateRegistration(t *testing.T) {
	t.Parallel()

	auth, err := NewAuthService(newMemoryUsers(), newMemoryRefreshTokens(), testSigningKey, time.Minute, time.Hour, 0)
	if err != nil {
		t.Fatal(err)
	}
	input := RegisterInput{Email: "user@example.com", Password: "password123", Nickname: "User"}
	if _, err := auth.Register(context.Background(), input); err != nil {
		t.Fatal(err)
	}
	if _, err := auth.Register(context.Background(), input); !errors.Is(err, ErrEmailTaken) {
		t.Fatalf("expected ErrEmailTaken, got %v", err)
	}
}

func TestRefreshTokenIsRotated(t *testing.T) {
	t.Parallel()

	auth, err := NewAuthService(newMemoryUsers(), newMemoryRefreshTokens(), testSigningKey, time.Minute, time.Hour, 0)
	if err != nil {
		t.Fatal(err)
	}
	result, err := auth.Register(context.Background(), RegisterInput{
		Email: "user@example.com", Password: "password123", Nickname: "User",
	})
	if err != nil {
		t.Fatal(err)
	}

	replacement, err := auth.Refresh(context.Background(), result.Tokens.RefreshToken, "new device")
	if err != nil {
		t.Fatal(err)
	}
	if replacement.RefreshToken == result.Tokens.RefreshToken {
		t.Fatal("refresh token was not rotated")
	}
	if _, err := auth.Refresh(context.Background(), result.Tokens.RefreshToken, "replay"); !errors.Is(err, ErrInvalidToken) {
		t.Fatalf("expected old token replay to fail, got %v", err)
	}
}

type memoryUsers struct {
	mu      sync.Mutex
	byID    map[string]*model.User
	byEmail map[string]*model.User
}

func newMemoryUsers() *memoryUsers {
	return &memoryUsers{byID: map[string]*model.User{}, byEmail: map[string]*model.User{}}
}

func (r *memoryUsers) Create(_ context.Context, user *model.User) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	if _, exists := r.byEmail[user.Email]; exists {
		return repository.ErrAlreadyExists
	}
	copy := *user
	r.byID[user.ID] = &copy
	r.byEmail[user.Email] = &copy
	return nil
}

func (r *memoryUsers) FindByEmail(_ context.Context, email string) (*model.User, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	user, exists := r.byEmail[email]
	if !exists {
		return nil, repository.ErrNotFound
	}
	copy := *user
	return &copy, nil
}

func (r *memoryUsers) FindByID(_ context.Context, id string) (*model.User, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	user, exists := r.byID[id]
	if !exists {
		return nil, repository.ErrNotFound
	}
	copy := *user
	return &copy, nil
}

type memoryRefreshTokens struct {
	mu     sync.Mutex
	byHash map[string]*model.RefreshToken
}

func newMemoryRefreshTokens() *memoryRefreshTokens {
	return &memoryRefreshTokens{byHash: map[string]*model.RefreshToken{}}
}

func (r *memoryRefreshTokens) Create(_ context.Context, token *model.RefreshToken) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	copy := *token
	r.byHash[token.TokenHash] = &copy
	return nil
}

func (r *memoryRefreshTokens) Rotate(
	_ context.Context,
	oldHash string,
	replacement *model.RefreshToken,
	now time.Time,
) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	current, exists := r.byHash[oldHash]
	if !exists || current.RevokedAt != nil || !current.ExpiresAt.After(now) || current.UserID != replacement.UserID {
		return repository.ErrTokenInvalid
	}
	current.RevokedAt = &now
	copy := *replacement
	r.byHash[replacement.TokenHash] = &copy
	return nil
}

func (r *memoryRefreshTokens) Revoke(_ context.Context, tokenHash string, now time.Time) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	if token, exists := r.byHash[tokenHash]; exists && token.RevokedAt == nil {
		token.RevokedAt = &now
	}
	return nil
}
