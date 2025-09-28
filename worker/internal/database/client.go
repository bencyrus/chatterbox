package database

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"

	"github.com/bencyrus/chatterbox/worker/internal/types"
	_ "github.com/lib/pq"
)

type Client struct {
	db *sql.DB
}

func NewClient(databaseURL string) (*Client, error) {
	db, err := sql.Open("postgres", databaseURL)
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %w", err)
	}

	if err := db.Ping(); err != nil {
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}

	return &Client{db: db}, nil
}

func (c *Client) Close() error {
	return c.db.Close()
}

// DequeueNextTask calls queues.dequeue_next_available_task() to get the next available task
func (c *Client) DequeueNextTask(ctx context.Context) (*types.Task, error) {
	var task types.Task
	var enqueuedAt, scheduledAt sql.NullTime
	var dequeuedAt sql.NullTime

	query := `SELECT * FROM queues.dequeue_next_available_task()`
	row := c.db.QueryRowContext(ctx, query)

	err := row.Scan(
		&task.TaskID,
		&task.TaskType,
		&task.Payload,
		&enqueuedAt,
		&scheduledAt,
		&dequeuedAt,
	)

	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil // No tasks available
		}
		return nil, fmt.Errorf("failed to dequeue task: %w", err)
	}

	// Convert nullable times
	if enqueuedAt.Valid {
		task.EnqueuedAt = enqueuedAt.Time
	}
	if scheduledAt.Valid {
		task.ScheduledAt = scheduledAt.Time
	}
	if dequeuedAt.Valid {
		task.DequeuedAt = &dequeuedAt.Time
	}

	return &task, nil
}

// RunFunction calls internal.run_function(function_name, payload) and returns the parsed result
// in DBFunctionResult (success, error, validation_failure_message, payload).
func (c *Client) RunFunction(ctx context.Context, functionName string, payload json.RawMessage) (*types.DBFunctionResult, error) {
	var resultJSON json.RawMessage

	query := `select internal.run_function($1, $2)`
	if err := c.db.QueryRowContext(ctx, query, functionName, payload).Scan(&resultJSON); err != nil {
		return nil, fmt.Errorf("failed to run function %s: %w", functionName, err)
	}

	var result types.DBFunctionResult
	if err := json.Unmarshal(resultJSON, &result); err != nil {
		return nil, fmt.Errorf("failed to unmarshal function result: %w", err)
	}
	return &result, nil
}

// AppendError calls queues.append_error(task_id, error_message) to record an error
func (c *Client) AppendError(ctx context.Context, taskID int64, errorMessage string) error {
	query := `select queues.append_error($1, $2)`
	var result json.RawMessage
	err := c.db.QueryRowContext(ctx, query, taskID, errorMessage).Scan(&result)
	if err != nil {
		return fmt.Errorf("failed to append error: %w", err)
	}
	return nil
}
