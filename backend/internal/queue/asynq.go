package queue

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/hibiken/asynq"
)

const ImageGenerateTaskType = "image:generate"

type ImageTaskPayload struct {
	TaskID string `json:"task_id"`
}

type AsynqImageQueue struct{ client *asynq.Client }

func NewAsynqImageQueue(redisAddress string) *AsynqImageQueue {
	return &AsynqImageQueue{client: asynq.NewClient(asynq.RedisClientOpt{Addr: redisAddress})}
}

func (q *AsynqImageQueue) Enqueue(ctx context.Context, taskID string) error {
	payload, err := json.Marshal(ImageTaskPayload{TaskID: taskID})
	if err != nil {
		return err
	}
	_, err = q.client.EnqueueContext(
		ctx,
		asynq.NewTask(ImageGenerateTaskType, payload),
		asynq.Queue("images"),
		asynq.MaxRetry(3),
		asynq.Unique(10*time.Minute),
	)
	if err != nil {
		return fmt.Errorf("enqueue image task: %w", err)
	}
	return nil
}

func (q *AsynqImageQueue) Close() error { return q.client.Close() }
