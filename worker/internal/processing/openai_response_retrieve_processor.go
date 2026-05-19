package processing

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/bencyrus/chatterbox/shared/logger"
	"github.com/bencyrus/chatterbox/worker/internal/services/openai"
	"github.com/bencyrus/chatterbox/worker/internal/types"
)

// OpenAIResponseRetrieveProcessor handles task_type == "openai_response_retrieve" by:
// - Calling the before_handler to resolve the OpenAI response id
// - Fetching the canonical response body from OpenAI
// - Returning the response body for the success handler to record
type OpenAIResponseRetrieveProcessor struct {
	handlers *HandlerInvoker
	service  *openai.Service
}

func NewOpenAIResponseRetrieveProcessor(
	handlers *HandlerInvoker,
	service *openai.Service,
) *OpenAIResponseRetrieveProcessor {
	return &OpenAIResponseRetrieveProcessor{
		handlers: handlers,
		service:  service,
	}
}

func (p *OpenAIResponseRetrieveProcessor) TaskType() string  { return "openai_response_retrieve" }
func (p *OpenAIResponseRetrieveProcessor) HasHandlers() bool { return true }

func (p *OpenAIResponseRetrieveProcessor) Process(ctx context.Context, task *types.Task) *types.TaskResult {
	var payload types.TaskPayload
	if err := json.Unmarshal(task.Payload, &payload); err != nil {
		return types.NewTaskFailure(fmt.Errorf("failed to unmarshal task payload: %w", err))
	}
	if payload.BeforeHandler == "" {
		return types.NewTaskFailure(fmt.Errorf("openai_response_retrieve task missing before_handler"))
	}

	var retrievePayload types.OpenAIResponseRetrievePayload
	if err := p.handlers.CallBefore(ctx, payload.BeforeHandler, task.Payload, &retrievePayload); err != nil {
		return types.NewTaskFailure(fmt.Errorf("openai_response_retrieve before_handler failed: %w", err))
	}

	logger.Info(ctx, "processing openai_response_retrieve task", logger.Fields{
		"attempt_id":         retrievePayload.OpenAIResponseAttemptID,
		"openai_response_id": retrievePayload.OpenAIResponseID,
	})

	result, err := p.service.RetrieveResponse(ctx, &retrievePayload)
	if err != nil {
		return types.NewTaskFailure(fmt.Errorf("OpenAI response retrieve error: %w", err))
	}

	return types.NewTaskSuccess(result)
}
