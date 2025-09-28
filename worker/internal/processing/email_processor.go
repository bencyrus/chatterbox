package processing

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/bencyrus/chatterbox/shared/logger"
	"github.com/bencyrus/chatterbox/worker/internal/services/email"
	"github.com/bencyrus/chatterbox/worker/internal/types"
)

type EmailProcessor struct {
	handlers *HandlerInvoker
	service  *email.Service
}

func NewEmailProcessor(handlers *HandlerInvoker, service *email.Service) *EmailProcessor {
	return &EmailProcessor{handlers: handlers, service: service}
}

func (p *EmailProcessor) TaskType() string  { return "email" }
func (p *EmailProcessor) HasHandlers() bool { return true }

func (p *EmailProcessor) Process(ctx context.Context, task *types.Task) *types.TaskResult {
	var payload types.TaskPayload
	if err := json.Unmarshal(task.Payload, &payload); err != nil {
		return types.NewTaskFailure(fmt.Errorf("failed to unmarshal task payload: %w", err))
	}
	if payload.BeforeHandler == "" {
		return types.NewTaskFailure(fmt.Errorf("email task missing before_handler"))
	}

	var emailPayload types.EmailPayload
	if err := p.handlers.CallBefore(ctx, payload.BeforeHandler, task.Payload, &emailPayload); err != nil {
		return types.NewTaskFailure(err)
	}

	logger.Info(ctx, "email payload prepared", logger.Fields{"message_id": emailPayload.MessageID})

	resp, err := p.service.SendEmail(ctx, &emailPayload)
	if err != nil {
		return types.NewTaskFailure(fmt.Errorf("failed to send email: %w", err))
	}

	return types.NewTaskSuccess(resp)
}
