package processing

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/bencyrus/chatterbox/worker/internal/services/sms"
	"github.com/bencyrus/chatterbox/worker/internal/types"
)

type SMSProcessor struct {
	handlers *HandlerInvoker
	service  *sms.Service
}

func NewSMSProcessor(handlers *HandlerInvoker, service *sms.Service) *SMSProcessor {
	return &SMSProcessor{handlers: handlers, service: service}
}

func (p *SMSProcessor) TaskType() string  { return "sms" }
func (p *SMSProcessor) HasHandlers() bool { return true }

func (p *SMSProcessor) Process(ctx context.Context, task *types.Task) *types.TaskResult {
	var payload types.TaskPayload
	if err := json.Unmarshal(task.Payload, &payload); err != nil {
		return types.NewTaskFailure(fmt.Errorf("failed to unmarshal task payload: %w", err))
	}
	if payload.BeforeHandler == "" {
		return types.NewTaskFailure(fmt.Errorf("sms task missing before_handler"))
	}

	var smsPayload types.SMSPayload
	if err := p.handlers.CallBefore(ctx, payload.BeforeHandler, task.Payload, &smsPayload); err != nil {
		return types.NewTaskFailure(err)
	}

	resp, err := p.service.SendSMS(ctx, &smsPayload)
	if err != nil {
		return types.NewTaskFailure(fmt.Errorf("failed to send SMS: %w", err))
	}

	return types.NewTaskSuccess(resp)
}
