package main

import (
	"context"
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/bencyrus/chatterbox/db-backup/internal/backup"
	"github.com/bencyrus/chatterbox/db-backup/internal/config"
	"github.com/bencyrus/chatterbox/db-backup/internal/upload"
	"github.com/bencyrus/chatterbox/shared/logger"
	"github.com/robfig/cron/v3"
)

func main() {
	cfg := config.Load()

	// Initialize the centralized logger
	logger.Init("db-backup")
	ctx := context.Background()

	logger.Info(ctx, "db-backup service starting", logger.Fields{
		"schedule":   cfg.BackupSchedule,
		"gcs_bucket": cfg.GCSBackupBucket,
		"gcs_prefix": cfg.GCSBackupPrefix,
	})

	// Run one immediate backup on startup
	logger.Info(ctx, "running immediate backup on startup")
	if err := runBackup(ctx, cfg); err != nil {
		logger.Error(ctx, "startup backup failed", err)
		log.Fatal(err)
	}

	// Set up cron scheduler
	c := cron.New()
	_, err := c.AddFunc(cfg.BackupSchedule, func() {
		logger.Info(ctx, "scheduled backup triggered")
		if err := runBackup(ctx, cfg); err != nil {
			logger.Error(ctx, "scheduled backup failed", err)
		}
	})
	if err != nil {
		logger.Error(ctx, "failed to add cron job", err)
		log.Fatal(err)
	}

	c.Start()
	logger.Info(ctx, "cron scheduler started", logger.Fields{
		"schedule": cfg.BackupSchedule,
	})

	// Wait for interrupt signal
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, os.Interrupt, syscall.SIGTERM)
	<-sigCh

	logger.Info(ctx, "shutdown signal received, stopping scheduler")
	c.Stop()
	logger.Info(ctx, "db-backup service stopped")
}

func runBackup(ctx context.Context, cfg config.Config) error {
	// 1. Create the dump
	backupPath, err := backup.CreateDump(ctx, cfg.PGHost, cfg.PGPort, cfg.PGUser, cfg.PGPassword)
	if err != nil {
		return err
	}

	// 2. Upload to GCS
	if err := upload.UploadToGCS(ctx, backupPath, cfg.GCSBackupBucket, cfg.GCSBackupPrefix, cfg.GCSServiceAccountEmail, cfg.GCSServiceAccountPrivateKey); err != nil {
		return err
	}

	// 3. Delete the local backup immediately after successful upload
	logger.Info(ctx, "deleting local backup after successful upload", logger.Fields{"path": backupPath})
	if err := os.Remove(backupPath); err != nil {
		logger.Warn(ctx, "failed to delete local backup (non-fatal)", logger.Fields{
			"path":  backupPath,
			"error": err.Error(),
		})
	}

	logger.Info(ctx, "backup cycle complete")
	return nil
}
