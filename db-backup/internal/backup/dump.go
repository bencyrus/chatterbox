package backup

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"time"

	"github.com/bencyrus/chatterbox/shared/logger"
)

const backupDir = "/backups"

// CreateDump creates a full cluster backup using pg_dumpall, writes it to /backups,
// and returns the path to the created .sql.gz file.
func CreateDump(ctx context.Context, pgHost, pgPort, pgUser, pgPassword string) (string, error) {
	timestamp := time.Now().UTC().Format("20060102T150405Z")
	filename := fmt.Sprintf("cluster_%s.sql.gz", timestamp)
	outputPath := filepath.Join(backupDir, filename)

	logger.Info(ctx, "creating postgres backup", logger.Fields{
		"pg_host": pgHost,
		"pg_port": pgPort,
		"pg_user": pgUser,
		"output":  outputPath,
	})

	// Ensure backup directory exists
	if err := os.MkdirAll(backupDir, 0755); err != nil {
		return "", fmt.Errorf("failed to create backup directory: %w", err)
	}

	// Build pg_dumpall command
	pgDumpall := exec.CommandContext(ctx, "pg_dumpall",
		"-h", pgHost,
		"-p", pgPort,
		"-U", pgUser,
	)
	pgDumpall.Env = append(os.Environ(), "PGPASSWORD="+pgPassword)

	// Build gzip command
	gzip := exec.CommandContext(ctx, "gzip", "-9")

	// Create output file
	outFile, err := os.Create(outputPath)
	if err != nil {
		return "", fmt.Errorf("failed to create output file: %w", err)
	}
	defer outFile.Close()

	// Pipe: pg_dumpall | gzip > outputPath
	pipe, err := pgDumpall.StdoutPipe()
	if err != nil {
		return "", fmt.Errorf("failed to create pipe: %w", err)
	}

	gzip.Stdin = pipe
	gzip.Stdout = outFile
	gzip.Stderr = os.Stderr
	pgDumpall.Stderr = os.Stderr

	// Start gzip first
	if err := gzip.Start(); err != nil {
		return "", fmt.Errorf("failed to start gzip: %w", err)
	}

	// Start pg_dumpall
	if err := pgDumpall.Start(); err != nil {
		return "", fmt.Errorf("failed to start pg_dumpall: %w", err)
	}

	// Wait for pg_dumpall to complete
	if err := pgDumpall.Wait(); err != nil {
		return "", fmt.Errorf("pg_dumpall failed: %w", err)
	}

	// Close the pipe so gzip knows to finish
	pipe.Close()

	// Wait for gzip to complete
	if err := gzip.Wait(); err != nil {
		return "", fmt.Errorf("gzip failed: %w", err)
	}

	logger.Info(ctx, "backup created successfully", logger.Fields{"path": outputPath})
	return outputPath, nil
}
