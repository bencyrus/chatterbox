package processing

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/bencyrus/chatterbox/shared/logger"
	"github.com/bencyrus/chatterbox/worker/internal/services/files"
	"github.com/bencyrus/chatterbox/worker/internal/types"
)

// FileDeleteProcessor handles task_type == "file_delete" by:
// - Calling the before_handler to resolve file_id, bucket, and object_key
// - Asking the files service for a signed delete URL
// - Issuing an HTTP DELETE against that URL
// Success and error facts are recorded via the standard handler flow.
type FileDeleteProcessor struct {
	handlers *HandlerInvoker
	service  *files.Service
}

func NewFileDeleteProcessor(handlers *HandlerInvoker, service *files.Service) *FileDeleteProcessor {
	return &FileDeleteProcessor{
		handlers: handlers,
		service:  service,
	}
}

func (p *FileDeleteProcessor) TaskType() string  { return "file_delete" }
func (p *FileDeleteProcessor) HasHandlers() bool { return true }

func (p *FileDeleteProcessor) Process(ctx context.Context, task *types.Task) *types.TaskResult {
	var payload types.TaskPayload
	if err := json.Unmarshal(task.Payload, &payload); err != nil {
		return types.NewTaskFailure(fmt.Errorf("failed to unmarshal task payload: %w", err))
	}
	if payload.BeforeHandler == "" {
		return types.NewTaskFailure(fmt.Errorf("file_delete task missing before_handler"))
	}

	var filePayload types.FileDeletePayload
	if err := p.handlers.CallBefore(ctx, payload.BeforeHandler, task.Payload, &filePayload); err != nil {
		return types.NewTaskFailure(fmt.Errorf("file_delete before_handler failed: %w", err))
	}

	logger.Info(ctx, "processing file_delete task", logger.Fields{
		"file_id":    filePayload.FileID,
		"bucket":     filePayload.Bucket,
		"object_key": filePayload.ObjectKey,
	})

	signedURL, err := p.service.GetSignedDeleteURL(ctx, filePayload.Bucket, filePayload.ObjectKey, filePayload.FileID)
	if err != nil {
		return types.NewTaskFailure(fmt.Errorf("failed to get signed delete URL: %w", err))
	}

	if err := p.service.DeleteBySignedURL(ctx, signedURL); err != nil {
		return types.NewTaskFailure(fmt.Errorf("failed to delete file via signed URL: %w", err))
	}

	result := &types.FileDeleteResult{
		FileID:          filePayload.FileID,
		Bucket:          filePayload.Bucket,
		ObjectKey:       filePayload.ObjectKey,
		DeleteStatus:    "deleted",
		SignedDeleteURL: signedURL,
	}

	return types.NewTaskSuccess(result)
}
