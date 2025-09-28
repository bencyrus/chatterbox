package supervisor

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/bencyrus/chatterbox/shared/logger"
	"github.com/bencyrus/chatterbox/worker/internal/database"
	"github.com/bencyrus/chatterbox/worker/internal/types"
)

type Service struct {
	db *database.Client
}

func NewService(db *database.Client) *Service {
	return &Service{
		db: db,
	}
}

// ExecuteDBFunction executes a database function (supervisor) task
func (s *Service) ExecuteDBFunction(ctx context.Context, task *types.Task) error {
	// Parse the payload to get the function name
	var payload types.TaskPayload
	if err := json.Unmarshal(task.Payload, &payload); err != nil {
		return fmt.Errorf("failed to unmarshal task payload: %w", err)
	}

	if payload.DBFunction == "" {
		return fmt.Errorf("db_function field is missing in payload")
	}

	logger.Info(ctx, "executing database function", logger.Fields{
		"task_id":   task.TaskID,
		"function":  payload.DBFunction,
		"task_type": task.TaskType,
	})

	// Call the database function
	result, err := s.db.RunFunction(ctx, payload.DBFunction, task.Payload)
	if err != nil {
		return fmt.Errorf("failed to execute database function %s: %w", payload.DBFunction, err)
	}

	// Check if the function returned an error or validation failure
	if result.Error != "" {
		return fmt.Errorf("database function %s returned error: %s", payload.DBFunction, result.Error)
	}

	if result.ValidationFailureMessage != "" {
		// Log validation failure but don't treat it as a fatal error
		logger.Warn(ctx, "database function returned validation failure", logger.Fields{
			"task_id":          task.TaskID,
			"function":         payload.DBFunction,
			"validation_error": result.ValidationFailureMessage,
		})
		// Record this as an error for observability
		if err := s.db.AppendError(ctx, task.TaskID, fmt.Sprintf("validation failure: %s", result.ValidationFailureMessage)); err != nil {
			logger.Error(ctx, "failed to append validation error", err)
		}
		return nil // Don't retry validation failures
	}

	logger.Info(ctx, "database function executed successfully", logger.Fields{
		"task_id":  task.TaskID,
		"function": payload.DBFunction,
		"success":  result.Success,
	})

	return nil
}
