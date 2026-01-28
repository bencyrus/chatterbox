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
// The function acquires a 5-minute lease on the task; if not completed before expiry, the task becomes available again
func (c *Client) DequeueNextTask(ctx context.Context) (*types.Task, error) {
	var task types.Task
	var taskID sql.NullInt64
	var taskType sql.NullString
	var payloadBytes []byte
	var enqueuedAt, scheduledAt sql.NullTime

	query := `select * from queues.dequeue_next_available_task()`
	row := c.db.QueryRowContext(ctx, query)

	err := row.Scan(
		&taskID,
		&taskType,
		&payloadBytes,
		&enqueuedAt,
		&scheduledAt,
	)

	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil // No tasks available
		}
		return nil, fmt.Errorf("failed to dequeue task: %w", err)
	}

	// Handle NULL composite (no task claimed)
	if !taskID.Valid {
		return nil, nil
	}

	task.TaskID = taskID.Int64
	if taskType.Valid {
		task.TaskType = taskType.String
	}
	if payloadBytes != nil {
		task.Payload = payloadBytes
	}
	if enqueuedAt.Valid {
		task.EnqueuedAt = enqueuedAt.Time
	}
	if scheduledAt.Valid {
		task.ScheduledAt = scheduledAt.Time
	}

	return &task, nil
}

// CompleteTask marks a task as completed so it won't be processed again
func (c *Client) CompleteTask(ctx context.Context, taskID int64) error {
	query := `select queues.complete_task($1)`
	_, err := c.db.ExecContext(ctx, query, taskID)
	if err != nil {
		return fmt.Errorf("failed to complete task: %w", err)
	}
	return nil
}

// FailTask records a task failure with an error message for observability
func (c *Client) FailTask(ctx context.Context, taskID int64, errorMessage string) error {
	query := `select queues.fail_task($1, $2)`
	_, err := c.db.ExecContext(ctx, query, taskID, errorMessage)
	if err != nil {
		return fmt.Errorf("failed to record task failure: %w", err)
	}
	return nil
}

// RunFunction calls internal.run_function(function_name, payload) and returns the parsed result
// in DBFunctionResult (status, payload). Status "succeeded" indicates success.
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
