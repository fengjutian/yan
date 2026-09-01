package repository

import "errors"

var (
	ErrNotFound      = errors.New("repository: not found")
	ErrAlreadyExists = errors.New("repository: already exists")
	ErrTokenInvalid  = errors.New("repository: refresh token invalid")
)
