package service

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/yan/ai-image-studio/backend/internal/model"
	"github.com/yan/ai-image-studio/backend/internal/repository"
)

func TestCreateImageTaskReservesCreditsAndEnqueues(t *testing.T) {
	t.Parallel()
	repo := &fakeTaskRepository{}
	taskQueue := &fakeImageQueue{}
	service := NewTaskService(repo, taskQueue, nil, nil)
	service.now = func() time.Time { return time.Date(2026, 9, 1, 10, 0, 0, 0, time.UTC) }

	task, err := service.Create(context.Background(), CreateImageTaskInput{
		UserID: "user-1", IdempotencyKey: "request-1", Prompt: "moon cat",
		AspectRatio: "1:1", Count: 2, PromptOptimizer: true, AIGCWatermark: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	if task.CreditsReserved != 20 || task.Status != "PENDING" {
		t.Fatalf("unexpected task: %+v", task)
	}
	if taskQueue.taskID != task.ID {
		t.Fatalf("task was not enqueued: %s", taskQueue.taskID)
	}
}

func TestCreateImageTaskRejectsInvalidRatio(t *testing.T) {
	t.Parallel()
	service := NewTaskService(&fakeTaskRepository{}, &fakeImageQueue{}, nil, nil)
	_, err := service.Create(context.Background(), CreateImageTaskInput{
		UserID: "user-1", IdempotencyKey: "request-1", Prompt: "cat",
		AspectRatio: "5:7", Count: 1,
	})
	if !errors.Is(err, ErrInvalidTask) {
		t.Fatalf("expected ErrInvalidTask, got %v", err)
	}
}

func TestQueueFailureRefundsTask(t *testing.T) {
	t.Parallel()
	repo := &fakeTaskRepository{}
	taskQueue := &fakeImageQueue{err: errors.New("redis unavailable")}
	service := NewTaskService(repo, taskQueue, nil, nil)
	_, err := service.Create(context.Background(), CreateImageTaskInput{
		UserID: "user-1", IdempotencyKey: "request-1", Prompt: "cat",
		AspectRatio: "1:1", Count: 1,
	})
	if err == nil || !repo.refunded {
		t.Fatalf("expected queue error and refund, err=%v refunded=%v", err, repo.refunded)
	}
}

func TestCreateTaskBuildsEffectiveStylePrompt(t *testing.T) {
	t.Parallel()
	repo := &fakeTaskRepository{}
	styleID := "style-1"
	service := NewTaskService(repo, &fakeImageQueue{}, nil, fakeStyles{})
	task, err := service.Create(context.Background(), CreateImageTaskInput{
		UserID: "user-1", IdempotencyKey: "request-style", Type: "TEXT_TO_IMAGE",
		Prompt: "portrait", StyleID: &styleID, AspectRatio: "1:1", Count: 1,
	})
	if err != nil {
		t.Fatal(err)
	}
	if task.EffectivePrompt == nil || *task.EffectivePrompt == task.Prompt {
		t.Fatalf("style template was not applied: %+v", task.EffectivePrompt)
	}
}

func TestTaskCursorRoundTrip(t *testing.T) {
	t.Parallel()
	createdAt := time.Date(2026, 9, 2, 9, 30, 0, 123, time.UTC)
	cursor := encodeTaskCursor(createdAt, "01J00000000000000000000099")
	decodedTime, decodedID, err := decodeTaskCursor(cursor)
	if err != nil {
		t.Fatal(err)
	}
	if !decodedTime.Equal(createdAt) || decodedID != "01J00000000000000000000099" {
		t.Fatalf("unexpected cursor result: %s %s", decodedTime, decodedID)
	}
}

type fakeImageQueue struct {
	taskID string
	err    error
}

func (q *fakeImageQueue) Enqueue(_ context.Context, taskID string) error {
	q.taskID = taskID
	return q.err
}

type fakeTaskRepository struct{ refunded bool }

type fakeStyles struct{}

func (fakeStyles) ListEnabled(context.Context) ([]model.Style, error) { return nil, nil }
func (fakeStyles) FindEnabledByID(_ context.Context, styleID string) (*model.Style, error) {
	return &model.Style{ID: styleID, PromptTemplate: "cinematic lighting"}, nil
}

func (r *fakeTaskRepository) CreatePending(
	_ context.Context,
	task *model.ImageTask,
	_, _ string,
) (*model.ImageTask, bool, error) {
	return task, false, nil
}

func (r *fakeTaskRepository) FindByID(_ context.Context, _, _ string) (*model.ImageTask, error) {
	return nil, repository.ErrNotFound
}

func (r *fakeTaskRepository) ResultAssetIDs(_ context.Context, _ string) ([]string, error) {
	return nil, nil
}

func (r *fakeTaskRepository) ListByUser(
	_ context.Context, _, _ string, _ time.Time, _ string, _ int,
) ([]model.ImageTask, error) {
	return nil, nil
}

func (r *fakeTaskRepository) Claim(_ context.Context, _ string) (*model.ImageTask, error) {
	return nil, repository.ErrNotFound
}

func (r *fakeTaskRepository) Succeed(_ context.Context, _, _ string, _ []string) error {
	return nil
}

func (r *fakeTaskRepository) FailAndRefund(_ context.Context, _, _, _ string) error {
	r.refunded = true
	return nil
}

func (r *fakeTaskRepository) CancelAndRefund(_ context.Context, _, _ string) error {
	r.refunded = true
	return nil
}
