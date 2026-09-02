package repository

import "errors"

var (
	ErrNotFound            = errors.New("repository: not found")
	ErrAlreadyExists       = errors.New("repository: already exists")
	ErrTokenInvalid        = errors.New("repository: refresh token invalid")
	ErrInsufficientCredits = errors.New("repository: insufficient credits")
	ErrIdempotencyConflict = errors.New("repository: idempotency conflict")
	ErrTaskNotCancelable   = errors.New("repository: task not cancelable")
)
