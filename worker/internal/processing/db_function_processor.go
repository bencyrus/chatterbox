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
	if result.Error != "" {
		return types.NewTaskFailure(fmt.Errorf("database function %s returned error: %s", payload.DBFunction, result.Error))
	}
	if result.ValidationFailureMessage != "" {
		// Not a fatal error; let the worker append error and continue
		logger.Warn(ctx, "database function returned validation failure", logger.Fields{
			"task_id":          task.TaskID,
			"function":         payload.DBFunction,
			"validation_error": result.ValidationFailureMessage,
		})
		return types.NewTaskSuccess(map[string]any{"validation_failure": result.ValidationFailureMessage})
	}

	return types.NewTaskSuccess(map[string]any{"success": true})
}
