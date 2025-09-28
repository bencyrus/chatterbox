package main

import (
	"context"
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/bencyrus/chatterbox/shared/logger"
	"github.com/bencyrus/chatterbox/worker/internal/config"
	"github.com/bencyrus/chatterbox/worker/internal/worker"
)

func main() {
	// Load configuration
	cfg := config.Load()

	// Initialize logger
	logger.Init("worker")
	ctx := context.Background()

	logger.Info(ctx, "starting chatterbox worker", logger.Fields{
		"poll_interval": cfg.PollInterval,
		"max_idle_time": cfg.MaxIdleTime,
		"log_level":     cfg.LogLevel,
		"concurrency":   cfg.Concurrency,
	})

	// Create worker
	w, err := worker.NewWorker(cfg)
	if err != nil {
		logger.Error(ctx, "failed to create worker", err)
		log.Fatalf("failed to create worker: %v", err)
	}
	defer w.Close()

	// Set up graceful shutdown
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	// Handle shutdown signals
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		sig := <-sigChan
		logger.Info(ctx, "received shutdown signal", logger.Fields{"signal": sig.String()})
		cancel()
	}()

	// Start worker
	logger.Info(ctx, "worker starting main loop")
	if err := w.Run(ctx); err != nil && err != context.Canceled {
		logger.Error(ctx, "worker error", err)
		log.Fatalf("worker error: %v", err)
	}

	logger.Info(ctx, "worker shutdown complete")
}
