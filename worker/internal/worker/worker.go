package worker

import (
	"context"
	"encoding/json"
	"fmt"
	"sync"
	"time"

	"github.com/bencyrus/chatterbox/shared/logger"
	"github.com/bencyrus/chatterbox/worker/internal/config"
	"github.com/bencyrus/chatterbox/worker/internal/database"
	"github.com/bencyrus/chatterbox/worker/internal/processing"
	"github.com/bencyrus/chatterbox/worker/internal/services/email"
	"github.com/bencyrus/chatterbox/worker/internal/services/sms"
	"github.com/bencyrus/chatterbox/worker/internal/types"
)

type Worker struct {
	cfg      config.Config
	db       *database.Client
	emailSvc *email.Service
	smsSvc   *sms.Service

	dispatcher *processing.Dispatcher
	handlers   *processing.HandlerInvoker
}

func NewWorker(cfg config.Config) (*Worker, error) {
	// Initialize database client
	db, err := database.NewClient(cfg.DatabaseURL)
	if err != nil {
		return nil, fmt.Errorf("failed to initialize database client: %w", err)
	}

	// Initialize services
	emailSvc := email.NewService(cfg.ResendAPIKey)
	smsSvc := sms.NewService()
	// Build processing stack
	handlers := processing.NewHandlerInvoker(db)
	dispatcher := processing.NewDispatcher()
	dispatcher.Register(processing.NewDBFunctionProcessor(db))
	dispatcher.Register(processing.NewEmailProcessor(handlers, emailSvc))
	dispatcher.Register(processing.NewSMSProcessor(handlers, smsSvc))

	return &Worker{
		cfg:        cfg,
		db:         db,
		emailSvc:   emailSvc,
		smsSvc:     smsSvc,
		dispatcher: dispatcher,
		handlers:   handlers,
	}, nil
}

func (w *Worker) Close() error {
	return w.db.Close()
}

// Run starts the worker loop
func (w *Worker) Run(ctx context.Context) error {
	logger.Info(ctx, "starting worker", logger.Fields{
		"poll_interval": w.cfg.PollInterval,
		"max_idle_time": w.cfg.MaxIdleTime,
		"concurrency":   w.cfg.Concurrency,
	})

	concurrency := w.cfg.Concurrency
	if concurrency < 1 {
		concurrency = 1
	}

	var wg sync.WaitGroup
	errCh := make(chan error, concurrency)

	startWorker := func(workerIndex int) {
		defer wg.Done()
		idleStart := time.Now()
		for {
			select {
			case <-ctx.Done():
				return
			default:
			}

			task, err := w.db.DequeueNextTask(ctx)
			if err != nil {
				logger.Error(ctx, "failed to dequeue task", err)
				time.Sleep(w.cfg.PollInterval)
				continue
			}
			if task == nil {
				if time.Since(idleStart) > w.cfg.MaxIdleTime {
					// keep alive, but log occasionally
					logger.Debug(ctx, "worker idle", logger.Fields{"worker": workerIndex})
				}
				time.Sleep(w.cfg.PollInterval)
				continue
			}

			idleStart = time.Now()

			if err := w.processTask(ctx, task); err != nil {
				logger.Error(ctx, "failed to process task", err, logger.Fields{
					"task_id":   task.TaskID,
					"task_type": task.TaskType,
				})
				if appendErr := w.db.AppendError(ctx, task.TaskID, err.Error()); appendErr != nil {
					logger.Error(ctx, "failed to append error to database", appendErr)
				}
				// do not emit to errCh; continue processing
			}
		}
	}

	wg.Add(concurrency)
	for i := 0; i < concurrency; i++ {
		go startWorker(i)
	}

	go func() {
		wg.Wait()
		close(errCh)
	}()

	select {
	case <-ctx.Done():
		return ctx.Err()
	case err := <-errCh:
		return err
	}
}

// processTask processes a single task based on its type
func (w *Worker) processTask(ctx context.Context, task *types.Task) error {
	logger.Info(ctx, "processing task", logger.Fields{
		"task_id":      task.TaskID,
		"task_type":    task.TaskType,
		"scheduled_at": task.ScheduledAt,
	})

	processor, err := w.dispatcher.Get(task)
	if err != nil {
		return err
	}
	result := processor.Process(ctx, task)
	return w.handleTaskResult(ctx, task, result)
}

// handleTaskResult handles the result of a task by calling appropriate handlers
func (w *Worker) handleTaskResult(ctx context.Context, task *types.Task, result *types.TaskResult) error {
	// Parse task payload to get handler names
	var payload types.TaskPayload
	if err := json.Unmarshal(task.Payload, &payload); err != nil {
		return fmt.Errorf("failed to unmarshal task payload: %w", err)
	}

	if result.Success {
		if payload.SuccessHandler != "" {
			if err := w.handlers.CallSuccess(ctx, payload.SuccessHandler, task.Payload, result.WorkerPayload); err != nil {
				logger.Error(ctx, "success handler failed", err)
			}
		}
	} else {
		if payload.ErrorHandler != "" {
			if err := w.handlers.CallError(ctx, payload.ErrorHandler, task.Payload, result.Error.Error()); err != nil {
				logger.Error(ctx, "error handler failed", err)
			}
		}
		return result.Error
	}

	return nil
}

// processDBFunctionTask handles database function (supervisor) tasks
// Removed per-processor implementations and handler calls in favor of processing package.
