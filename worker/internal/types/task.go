package types

import (
	"encoding/json"
	"time"
)

// Task represents a task from the queues.task table
type Task struct {
	TaskID      int64           `json:"task_id"`
	TaskType    string          `json:"task_type"`
	Payload     json.RawMessage `json:"payload"`
	EnqueuedAt  time.Time       `json:"enqueued_at"`
	ScheduledAt time.Time       `json:"scheduled_at"`
	DequeuedAt  *time.Time      `json:"dequeued_at"`
}

// TaskPayload represents the common structure of task payloads
// The worker only needs to know about the handler fields - all business-specific
// data stays in the original task.Payload and gets passed through to handlers
type TaskPayload struct {
	TaskType       string `json:"task_type"`
	DBFunction     string `json:"db_function,omitempty"`
	BeforeHandler  string `json:"before_handler,omitempty"`
	SuccessHandler string `json:"success_handler,omitempty"`
	ErrorHandler   string `json:"error_handler,omitempty"`

	// Note: No business-specific fields here!
	// The database functions receive the full original task.Payload
	// and extract whatever IDs/data they need from it
}

// HandlerPayload represents the payload structure for success/error handlers
type HandlerPayload struct {
	OriginalPayload json.RawMessage `json:"original_payload,omitempty"`
	WorkerPayload   json.RawMessage `json:"worker_payload,omitempty"`
	Error           string          `json:"error,omitempty"`
}

// DBFunctionResult represents the result from a database function call
type DBFunctionResult struct {
	Success                  bool            `json:"success,omitempty"`
	Error                    string          `json:"error,omitempty"`
	ValidationFailureMessage string          `json:"validation_failure_message,omitempty"`
	Payload                  json.RawMessage `json:"payload,omitempty"`
}

// TaskResult represents the result of processing a task
type TaskResult struct {
	Success       bool
	WorkerPayload any   // The result data from the service (email response, sms response, etc.)
	Error         error // Any error that occurred
}

// NewTaskSuccess creates a successful task result
func NewTaskSuccess(workerPayload any) *TaskResult {
	return &TaskResult{
		Success:       true,
		WorkerPayload: workerPayload,
	}
}

// NewTaskFailure creates a failed task result
func NewTaskFailure(err error) *TaskResult {
	return &TaskResult{
		Success: false,
		Error:   err,
	}
}
