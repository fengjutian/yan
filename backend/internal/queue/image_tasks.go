package queue

import "context"

type ImageTaskQueue interface {
	Enqueue(ctx context.Context, taskID string) error
}
