package processing

import (
	"context"

	"github.com/bencyrus/chatterbox/worker/internal/types"
)

// Processor defines the contract for handling a specific task type.
// Implementations should contain minimal orchestration logic and delegate
// provider-specific work to services. Processors must be idempotent.
type Processor interface {
	// TaskType returns the queues.task_type handled by this processor (e.g., "email").
	TaskType() string
	// HasHandlers indicates whether the processor expects before/success/error handlers.
	HasHandlers() bool
	// Process performs the unit of work and returns a TaskResult. It must not enqueue.
	Process(ctx context.Context, task *types.Task) *types.TaskResult
}
