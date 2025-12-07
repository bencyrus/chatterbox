package files

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"time"

	"github.com/bencyrus/chatterbox/gateway/internal/config"
	"github.com/bencyrus/chatterbox/shared/logger"
)

// InjectSignedFileURLs inspects the JSON response payload. If it contains an array field
// configured by cfg.FilesFieldName, it calls the file service signed URL endpoint with the array
// and, on success, injects a field configured by cfg.ProcessedFilesFieldName that contains the
// service's response while keeping the original files field intact.
func InjectSignedFileURLs(ctx context.Context, cfg config.Config, body []byte) ([]byte, error) {
	var generic map[string]any
	if err := json.Unmarshal(body, &generic); err != nil {
		// Not JSON or not an object; return original body without error
		return body, nil
	}

	filesRaw, ok := generic[cfg.FilesFieldName]
	if !ok {
		return body, nil
	}

	filesSlice, ok := filesRaw.([]any)
	if !ok || len(filesSlice) == 0 {
		return body, nil
	}

	logger.Debug(ctx, "processing file URLs", logger.Fields{
		"files_count":      len(filesSlice),
		"file_service_url": cfg.FileServiceURL + cfg.FileSignedDownloadURLPath,
	})

	client := &http.Client{Timeout: time.Duration(cfg.HTTPClientTimeoutSeconds) * time.Second}
	url := cfg.FileServiceURL + cfg.FileSignedDownloadURLPath
	payload := map[string]any{"files": filesSlice}
	reqBody, err := json.Marshal(payload)
	if err != nil {
		logger.Error(ctx, "failed to marshal file service payload", err)
		return body, nil
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(reqBody))
	if err != nil {
		logger.Error(ctx, "failed to create file service request", err)
		return body, nil
	}
	req.Header.Set("Content-Type", "application/json")
	if cfg.FileServiceAPIKey != "" {
		req.Header.Set("X-File-Service-Api-Key", cfg.FileServiceAPIKey)
	}

	resp, err := client.Do(req)
	if err != nil {
		logger.Error(ctx, "file service request failed", err)
		return body, nil
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		logger.Warn(ctx, "file service returned error status", logger.Fields{
			"status_code": resp.StatusCode,
		})
		return body, nil
	}

	var serviceJSON any
	if err := json.NewDecoder(resp.Body).Decode(&serviceJSON); err != nil {
		logger.Error(ctx, "failed to decode file service response", err)
		return body, nil
	}

	generic[cfg.ProcessedFilesFieldName] = serviceJSON
	newBody, err := json.Marshal(generic)
	if err != nil {
		logger.Error(ctx, "failed to marshal updated response", err)
		return body, nil
	}

	logger.Info(ctx, "file URLs processed successfully")
	return newBody, nil
}

// InjectSignedUploadURL inspects the JSON response payload. If it contains a field
// configured by cfg.UploadIntentFieldName, it calls the file service signed upload URL endpoint
// and injects a field configured by cfg.UploadURLFieldName that contains the signed upload URL.
func InjectSignedUploadURL(ctx context.Context, cfg config.Config, body []byte) ([]byte, error) {
	var generic map[string]any
	if err := json.Unmarshal(body, &generic); err != nil {
		// Not JSON or not an object; return original body without error
		return body, nil
	}

	uploadIntentID, ok := generic[cfg.UploadIntentFieldName]
	if !ok {
		return body, nil
	}

	logger.Debug(ctx, "processing upload URL", logger.Fields{
		"file_service_url": cfg.FileServiceURL + cfg.FileSignedUploadURLPath,
	})

	client := &http.Client{Timeout: time.Duration(cfg.HTTPClientTimeoutSeconds) * time.Second}
	url := cfg.FileServiceURL + cfg.FileSignedUploadURLPath
	payload := map[string]any{"upload_intent_id": uploadIntentID}
	reqBody, err := json.Marshal(payload)
	if err != nil {
		logger.Error(ctx, "failed to marshal file service upload payload", err)
		return body, nil
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(reqBody))
	if err != nil {
		logger.Error(ctx, "failed to create file service upload request", err)
		return body, nil
	}
	req.Header.Set("Content-Type", "application/json")
	if cfg.FileServiceAPIKey != "" {
		req.Header.Set("X-File-Service-Api-Key", cfg.FileServiceAPIKey)
	}

	resp, err := client.Do(req)
	if err != nil {
		logger.Error(ctx, "file service upload request failed", err)
		return body, nil
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		logger.Warn(ctx, "file service returned error status for upload URL", logger.Fields{
			"status_code": resp.StatusCode,
		})
		return body, nil
	}

	var serviceResponse map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&serviceResponse); err != nil {
		logger.Error(ctx, "failed to decode file service upload response", err)
		return body, nil
	}

	// Inject the upload_url field
	if uploadURL, ok := serviceResponse["upload_url"]; ok {
		generic[cfg.UploadURLFieldName] = uploadURL
	}

	newBody, err := json.Marshal(generic)
	if err != nil {
		logger.Error(ctx, "failed to marshal updated response with upload URL", err)
		return body, nil
	}

	logger.Info(ctx, "upload URL processed successfully")
	return newBody, nil
}
