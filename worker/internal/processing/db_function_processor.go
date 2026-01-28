package processing

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/bencyrus/chatterbox/shared/logger"
	"github.com/bencyrus/chatterbox/worker/internal/database"
	"github.com/bencyrus/chatterbox/worker/internal/types"
)

type DBFunctionProcessor struct {
	db *database.Client
}

func NewDBFunctionProcessor(db *database.Client) *DBFunctionProcessor {
	return &DBFunctionProcessor{db: db}
}

func (p *DBFunctionProcessor) TaskType() string  { return "db_function" }
func (p *DBFunctionProcessor) HasHandlers() bool { return false }

func (p *DBFunctionProcessor) Process(ctx context.Context, task *types.Task) *types.TaskResult {
	var payload types.TaskPayload
	if err := json.Unmarshal(task.Payload, &payload); err != nil {
		return types.NewTaskFailure(fmt.Errorf("failed to unmarshal task payload: %w", err))
	}
	if payload.DBFunction == "" {
		return types.NewTaskFailure(fmt.Errorf("db_function field is missing in payload"))
	}

	logger.Info(ctx, "executing database function", logger.Fields{
		"task_id":   task.TaskID,
		"function":  payload.DBFunction,
		"task_type": task.TaskType,
	})

	result, err := p.db.RunFunction(ctx, payload.DBFunction, task.Payload)
	if err != nil {
		return types.NewTaskFailure(fmt.Errorf("failed to execute database function %s: %w", payload.DBFunction, err))
	}
	if !result.IsSuccess() {
		// Non-succeeded status is logged but not treated as fatal - the supervisor pattern
		// uses status values to communicate outcomes without raising errors
		logger.Info(ctx, "database function returned non-success status", logger.Fields{
			"task_id":  task.TaskID,
			"function": payload.DBFunction,
			"status":   result.Status,
		})
	}

	return types.NewTaskSuccess(map[string]any{"status": result.Status})
}
