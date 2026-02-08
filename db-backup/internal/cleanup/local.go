package cleanup

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/bencyrus/chatterbox/shared/logger"
)

const backupDir = "/backups"
const backupPattern = "cluster_*.sql.gz"

// CleanupOldBackups removes local backup files older than the specified number of days.
func CleanupOldBackups(ctx context.Context, retentionDays int) error {
	if retentionDays <= 0 {
		logger.Info(ctx, "local cleanup disabled (retention days <= 0)", logger.Fields{
			"retention_days": retentionDays,
		})
		return nil
	}

	cutoffTime := time.Now().Add(-time.Duration(retentionDays) * 24 * time.Hour)

	logger.Info(ctx, "cleaning up old local backups", logger.Fields{
		"retention_days": retentionDays,
		"cutoff_time":    cutoffTime.Format(time.RFC3339),
	})

	pattern := filepath.Join(backupDir, backupPattern)
	matches, err := filepath.Glob(pattern)
	if err != nil {
		return fmt.Errorf("failed to glob backup files: %w", err)
	}

	deletedCount := 0
	for _, path := range matches {
		info, err := os.Stat(path)
		if err != nil {
			logger.Warn(ctx, "failed to stat backup file", logger.Fields{
				"path":  path,
				"error": err.Error(),
			})
			continue
		}

		if info.ModTime().Before(cutoffTime) {
			logger.Info(ctx, "deleting old backup", logger.Fields{
				"path":     path,
				"mod_time": info.ModTime().Format(time.RFC3339),
			})

			if err := os.Remove(path); err != nil {
				logger.Error(ctx, "failed to delete backup file", err, logger.Fields{
					"path": path,
				})
			} else {
				deletedCount++
			}
		}
	}

	logger.Info(ctx, "local cleanup complete", logger.Fields{
		"deleted_count": deletedCount,
	})

	return nil
}
