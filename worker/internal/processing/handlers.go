package processing

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/bencyrus/chatterbox/worker/internal/database"
	"github.com/bencyrus/chatterbox/worker/internal/types"
)

// HandlerInvoker centralizes invocation of before/success/error handlers.
type HandlerInvoker struct {
	db *database.Client
}

func NewHandlerInvoker(db *database.Client) *HandlerInvoker {
	return &HandlerInvoker{db: db}
}

// CallBefore expects handler to return DBFunctionResult with payload.
// The payload is unmarshaled into target.
func (h *HandlerInvoker) CallBefore(ctx context.Context, handlerName string, originalPayload json.RawMessage, target any) error {
	result, err := h.db.RunFunction(ctx, handlerName, originalPayload)
	if err != nil {
		return fmt.Errorf("before handler %s failed: %w", handlerName, err)
	}
	if result.Error != "" {
		return fmt.Errorf("before handler %s returned error: %s", handlerName, result.Error)
	}
	if result.ValidationFailureMessage != "" {
		return fmt.Errorf(result.ValidationFailureMessage)
	}
	if !result.Success || len(result.Payload) == 0 {
		return fmt.Errorf("before handler %s did not return payload", handlerName)
	}
	if err := json.Unmarshal(result.Payload, target); err != nil {
		return fmt.Errorf("failed to unmarshal before payload: %w", err)
	}
	return nil
}

func (h *HandlerInvoker) CallSuccess(ctx context.Context, handlerName string, originalPayload json.RawMessage, workerResult any) error {
	workerPayloadBytes, err := json.Marshal(workerResult)
	if err != nil {
		return fmt.Errorf("failed to marshal worker result: %w", err)
	}

	payload := types.HandlerPayload{
		OriginalPayload: originalPayload,
		WorkerPayload:   workerPayloadBytes,
	}
	payloadBytes, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("failed to marshal handler payload: %w", err)
	}

	_, err = h.db.RunFunction(ctx, handlerName, payloadBytes)
	return err
}

func (h *HandlerInvoker) CallError(ctx context.Context, handlerName string, originalPayload json.RawMessage, errorMessage string) error {
	payload := types.HandlerPayload{
		OriginalPayload: originalPayload,
		Error:           errorMessage,
	}
	payloadBytes, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("failed to marshal handler payload: %w", err)
	}

	_, err = h.db.RunFunction(ctx, handlerName, payloadBytes)
	return err
}
