package service

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"net/mail"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/oklog/ulid/v2"
	"github.com/yan/ai-image-studio/backend/internal/model"
	"github.com/yan/ai-image-studio/backend/internal/repository"
	"golang.org/x/crypto/bcrypt"
)

var (
	ErrEmailTaken         = errors.New("auth: email already registered")
	ErrInvalidCredentials = errors.New("auth: invalid credentials")
	ErrInvalidToken       = errors.New("auth: invalid token")
	ErrInvalidInput       = errors.New("auth: invalid input")
	ErrUserDisabled       = errors.New("auth: user disabled")
)

type AuthService struct {
	users           repository.UserRepository
	refreshTokens   repository.RefreshTokenRepository
	signingKey      []byte
	accessTokenTTL  time.Duration
	refreshTokenTTL time.Duration
	initialCredits  int64
	now             func() time.Time
}

type RegisterInput struct {
	Email      string
	Password   string
	Nickname   string
	DeviceName string
}

type LoginInput struct {
	Email      string
	Password   string
	DeviceName string
}

type TokenPair struct {
	AccessToken      string
	RefreshToken     string
	AccessExpiresAt  time.Time
	RefreshExpiresAt time.Time
}

type AuthResult struct {
	User   *model.User
	Tokens TokenPair
}

type AccessClaims struct {
	jwt.RegisteredClaims
	TokenType string `json:"token_type"`
}

func NewAuthService(
	users repository.UserRepository,
	refreshTokens repository.RefreshTokenRepository,
	signingKey string,
	accessTokenTTL time.Duration,
	refreshTokenTTL time.Duration,
	initialCredits int64,
) (*AuthService, error) {
	if len(signingKey) < 32 {
		return nil, fmt.Errorf("JWT_SIGNING_KEY must contain at least 32 bytes")
	}
	return &AuthService{
		users:           users,
		refreshTokens:   refreshTokens,
		signingKey:      []byte(signingKey),
		accessTokenTTL:  accessTokenTTL,
		refreshTokenTTL: refreshTokenTTL,
		initialCredits:  initialCredits,
		now:             time.Now,
	}, nil
}

func (s *AuthService) Register(ctx context.Context, input RegisterInput) (*AuthResult, error) {
	email, err := normalizeEmail(input.Email)
	if err != nil || len(input.Password) < 8 || len(input.Password) > 72 {
		return nil, ErrInvalidInput
	}
	nickname := strings.TrimSpace(input.Nickname)
	if nickname == "" || len([]rune(nickname)) > 80 {
		return nil, ErrInvalidInput
	}

	passwordHash, err := bcrypt.GenerateFromPassword([]byte(input.Password), bcrypt.DefaultCost)
	if err != nil {
		return nil, fmt.Errorf("hash password: %w", err)
	}
	now := s.now().UTC()
	user := &model.User{
		ID:             ulid.Make().String(),
		Email:          email,
		PasswordHash:   string(passwordHash),
		Nickname:       nickname,
		Status:         "ACTIVE",
		CreditsBalance: s.initialCredits,
		CreatedAt:      now,
		UpdatedAt:      now,
	}
	if err := s.users.Create(ctx, user); err != nil {
		if errors.Is(err, repository.ErrAlreadyExists) {
			return nil, ErrEmailTaken
		}
		return nil, fmt.Errorf("create user: %w", err)
	}

	tokens, refreshRecord, err := s.newTokenPair(user.ID, input.DeviceName, now)
	if err != nil {
		return nil, err
	}
	if err := s.refreshTokens.Create(ctx, refreshRecord); err != nil {
		return nil, fmt.Errorf("store refresh token: %w", err)
	}
	return &AuthResult{User: user, Tokens: tokens}, nil
}

func (s *AuthService) Login(ctx context.Context, input LoginInput) (*AuthResult, error) {
	email, err := normalizeEmail(input.Email)
	if err != nil {
		return nil, ErrInvalidCredentials
	}
	user, err := s.users.FindByEmail(ctx, email)
	if errors.Is(err, repository.ErrNotFound) {
		return nil, ErrInvalidCredentials
	}
	if err != nil {
		return nil, fmt.Errorf("find user: %w", err)
	}
	if bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(input.Password)) != nil {
		return nil, ErrInvalidCredentials
	}
	if user.Status != "ACTIVE" {
		return nil, ErrUserDisabled
	}

	now := s.now().UTC()
	tokens, refreshRecord, err := s.newTokenPair(user.ID, input.DeviceName, now)
	if err != nil {
		return nil, err
	}
	if err := s.refreshTokens.Create(ctx, refreshRecord); err != nil {
		return nil, fmt.Errorf("store refresh token: %w", err)
	}
	return &AuthResult{User: user, Tokens: tokens}, nil
}

func (s *AuthService) Refresh(ctx context.Context, rawToken, deviceName string) (*TokenPair, error) {
	oldHash := hashToken(rawToken)
	userID, err := refreshTokenUserID(rawToken)
	if err != nil {
		return nil, ErrInvalidToken
	}
	user, err := s.users.FindByID(ctx, userID)
	if err != nil || user.Status != "ACTIVE" {
		return nil, ErrInvalidToken
	}

	now := s.now().UTC()
	tokens, replacement, err := s.newTokenPair(user.ID, deviceName, now)
	if err != nil {
		return nil, err
	}
	if err := s.refreshTokens.Rotate(ctx, oldHash, replacement, now); err != nil {
		if errors.Is(err, repository.ErrTokenInvalid) {
			return nil, ErrInvalidToken
		}
		return nil, fmt.Errorf("rotate refresh token: %w", err)
	}
	return &tokens, nil
}

func (s *AuthService) Logout(ctx context.Context, rawToken string) error {
	if rawToken == "" {
		return ErrInvalidToken
	}
	if err := s.refreshTokens.Revoke(ctx, hashToken(rawToken), s.now().UTC()); err != nil {
		return fmt.Errorf("revoke refresh token: %w", err)
	}
	return nil
}

func (s *AuthService) AuthenticateAccessToken(rawToken string) (string, error) {
	claims := &AccessClaims{}
	token, err := jwt.ParseWithClaims(rawToken, claims, func(token *jwt.Token) (any, error) {
		if token.Method != jwt.SigningMethodHS256 {
			return nil, ErrInvalidToken
		}
		return s.signingKey, nil
	}, jwt.WithExpirationRequired(), jwt.WithIssuedAt(), jwt.WithTimeFunc(s.now))
	if err != nil || !token.Valid || claims.TokenType != "access" || claims.Subject == "" {
		return "", ErrInvalidToken
	}
	return claims.Subject, nil
}

func (s *AuthService) FindUser(ctx context.Context, userID string) (*model.User, error) {
	user, err := s.users.FindByID(ctx, userID)
	if errors.Is(err, repository.ErrNotFound) {
		return nil, ErrInvalidToken
	}
	return user, err
}

func (s *AuthService) newTokenPair(userID, deviceName string, now time.Time) (TokenPair, *model.RefreshToken, error) {
	accessExpiresAt := now.Add(s.accessTokenTTL)
	claims := AccessClaims{
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   userID,
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(accessExpiresAt),
		},
		TokenType: "access",
	}
	accessToken, err := jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString(s.signingKey)
	if err != nil {
		return TokenPair{}, nil, fmt.Errorf("sign access token: %w", err)
	}

	randomPart := make([]byte, 32)
	if _, err := rand.Read(randomPart); err != nil {
		return TokenPair{}, nil, fmt.Errorf("generate refresh token: %w", err)
	}
	refreshToken := userID + "." + base64.RawURLEncoding.EncodeToString(randomPart)
	refreshExpiresAt := now.Add(s.refreshTokenTTL)
	record := &model.RefreshToken{
		ID:         ulid.Make().String(),
		UserID:     userID,
		TokenHash:  hashToken(refreshToken),
		ExpiresAt:  refreshExpiresAt,
		DeviceName: strings.TrimSpace(deviceName),
		CreatedAt:  now,
	}
	return TokenPair{
		AccessToken:      accessToken,
		RefreshToken:     refreshToken,
		AccessExpiresAt:  accessExpiresAt,
		RefreshExpiresAt: refreshExpiresAt,
	}, record, nil
}

func normalizeEmail(raw string) (string, error) {
	normalized := strings.ToLower(strings.TrimSpace(raw))
	address, err := mail.ParseAddress(normalized)
	if err != nil || address.Address != normalized || len(normalized) > 255 {
		return "", ErrInvalidInput
	}
	return normalized, nil
}

func hashToken(raw string) string {
	sum := sha256.Sum256([]byte(raw))
	return hex.EncodeToString(sum[:])
}

func refreshTokenUserID(raw string) (string, error) {
	userID, randomPart, ok := strings.Cut(raw, ".")
	if !ok || len(userID) != 26 || randomPart == "" {
		return "", ErrInvalidToken
	}
	if _, err := base64.RawURLEncoding.DecodeString(randomPart); err != nil {
		return "", ErrInvalidToken
	}
	return userID, nil
}
