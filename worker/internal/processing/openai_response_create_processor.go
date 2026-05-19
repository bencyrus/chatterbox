package processing

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/bencyrus/chatterbox/shared/logger"
	"github.com/bencyrus/chatterbox/worker/internal/services/openai"
	"github.com/bencyrus/chatterbox/worker/internal/types"
)

// OpenAIResponseCreateProcessor handles task_type == "openai_response_create" by:
// - Calling the before_handler to resolve the attempt id and request body
// - Calling OpenAI's Responses API
// - Returning the response id and body for the success handler to record
type OpenAIResponseCreateProcessor struct {
	handlers *HandlerInvoker
	service  *openai.Service
}

func NewOpenAIResponseCreateProcessor(
	handlers *HandlerInvoker,
	service *openai.Service,
) *OpenAIResponseCreateProcessor {
	return &OpenAIResponseCreateProcessor{
		handlers: handlers,
		service:  service,
	}
}

func (p *OpenAIResponseCreateProcessor) TaskType() string  { return "openai_response_create" }
func (p *OpenAIResponseCreateProcessor) HasHandlers() bool { return true }

func (p *OpenAIResponseCreateProcessor) Process(ctx context.Context, task *types.Task) *types.TaskResult {
	var payload types.TaskPayload
	if err := json.Unmarshal(task.Payload, &payload); err != nil {
		return types.NewTaskFailure(fmt.Errorf("failed to unmarshal task payload: %w", err))
	}
	if payload.BeforeHandler == "" {
		return types.NewTaskFailure(fmt.Errorf("openai_response_create task missing before_handler"))
	}

	var createPayload types.OpenAIResponseCreatePayload
	if err := p.handlers.CallBefore(ctx, payload.BeforeHandler, task.Payload, &createPayload); err != nil {
		return types.NewTaskFailure(fmt.Errorf("openai_response_create before_handler failed: %w", err))
	}

	logger.Info(ctx, "processing openai_response_create task", logger.Fields{
		"attempt_id": createPayload.OpenAIResponseAttemptID,
	})

	result, err := p.service.CreateResponse(ctx, &createPayload)
	if err != nil {
		return types.NewTaskFailure(fmt.Errorf("OpenAI response create error: %w", err))
	}

	return types.NewTaskSuccess(result)
}
