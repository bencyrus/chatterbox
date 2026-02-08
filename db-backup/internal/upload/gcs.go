package upload

import (
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"cloud.google.com/go/storage"
	"github.com/bencyrus/chatterbox/shared/logger"
	"google.golang.org/api/option"
)

// UploadToGCS uploads the specified file to GCS using the provided credentials.
func UploadToGCS(ctx context.Context, filePath, bucket, prefix, serviceAccountEmail, privateKey string) error {
	filename := filepath.Base(filePath)
	objectKey := filepath.Join(prefix, filename)

	logger.Info(ctx, "uploading backup to GCS", logger.Fields{
		"file":   filePath,
		"bucket": bucket,
		"key":    objectKey,
	})

	// Convert literal \n sequences back into real newlines for the private key
	key := strings.ReplaceAll(privateKey, `\n`, "\n")

	// Build credentials JSON
	credJSON := fmt.Sprintf(`{
  "type": "service_account",
  "client_email": "%s",
  "private_key": "%s",
  "token_uri": "https://oauth2.googleapis.com/token"
}`, serviceAccountEmail, strings.ReplaceAll(key, "\n", "\\n"))

	// Create GCS client
	client, err := storage.NewClient(ctx, option.WithCredentialsJSON([]byte(credJSON)))
	if err != nil {
		return fmt.Errorf("failed to create GCS client: %w", err)
	}
	defer client.Close()

	// Open the file
	file, err := os.Open(filePath)
	if err != nil {
		return fmt.Errorf("failed to open file: %w", err)
	}
	defer file.Close()

	// Get file info for logging
	fileInfo, err := file.Stat()
	if err != nil {
		return fmt.Errorf("failed to stat file: %w", err)
	}

	// Create a writer to the GCS object
	obj := client.Bucket(bucket).Object(objectKey)
	writer := obj.NewWriter(ctx)
	writer.ContentType = "application/gzip"

	// Copy file contents to GCS
	bytesWritten, err := io.Copy(writer, file)
	if err != nil {
		writer.Close()
		return fmt.Errorf("failed to upload to GCS: %w", err)
	}

	// Close the writer (finalizes the upload)
	if err := writer.Close(); err != nil {
		return fmt.Errorf("failed to finalize GCS upload: %w", err)
	}

	logger.Info(ctx, "upload to GCS complete", logger.Fields{
		"bucket":        bucket,
		"key":           objectKey,
		"bytes":         bytesWritten,
		"original_size": fileInfo.Size(),
	})

	return nil
}
