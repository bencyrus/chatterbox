package files

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/url"
	"net/http"
	"strings"
	"time"

	"github.com/bencyrus/chatterbox/shared/logger"
	"github.com/bencyrus/chatterbox/worker/internal/types"
)

// Service provides an HTTP client wrapper around the files service for
// operations related to file deletion.
type Service struct {
	baseURL    string
	apiKey     string
	httpClient *http.Client
}

// NewService constructs a new files Service client.
func NewService(baseURL, apiKey string) *Service {
	normalized := strings.TrimRight(strings.TrimSpace(baseURL), "/")
	return &Service{
		baseURL: normalized,
		apiKey:  strings.TrimSpace(apiKey),
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
	}
}

// GetSignedDeleteURL requests a signed DELETE URL for a specific file from
// the files service. The files service is responsible for resolving storage
// details (bucket, object key) from the file ID so the worker does not need
// to know about them.
func (s *Service) GetSignedDeleteURL(ctx context.Context, fileID int64) (string, error) {
	if s.baseURL == "" {
		return "", fmt.Errorf("files service baseURL is empty")
	}
	if s.apiKey == "" {
		return "", fmt.Errorf("files service api key is empty")
	}

	logger.Info(ctx, "requesting signed delete URL from files service", logger.Fields{
		"file_id": fileID,
	})

	body := map[string]any{
		"file_id": fileID,
	}

	reqBody, err := json.Marshal(body)
	if err != nil {
		return "", fmt.Errorf("failed to marshal signed delete url request: %w", err)
	}

	url := s.baseURL + "/signed_delete_url"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(reqBody))
	if err != nil {
		return "", fmt.Errorf("failed to create signed delete url request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-File-Service-Api-Key", s.apiKey)

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("failed to call files service signed_delete_url: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		return "", fmt.Errorf("files service signed_delete_url returned status %d", resp.StatusCode)
	}

	var parsed types.FileSignedDeleteURLResponse
	if err := json.NewDecoder(resp.Body).Decode(&parsed); err != nil {
		return "", fmt.Errorf("failed to decode signed_delete_url response: %w", err)
	}
	if parsed.URL == "" {
		return "", fmt.Errorf("files service signed_delete_url response missing url")
	}

	logger.Info(ctx, "received signed delete URL from files service", logger.Fields{
		"file_id": fileID,
	})

	return parsed.URL, nil
}

// DeleteBySignedURL performs an HTTP DELETE against the provided signed URL.
func (s *Service) DeleteBySignedURL(ctx context.Context, signedURL string) error {
	if signedURL == "" {
		return fmt.Errorf("signed delete URL is empty")
	}

	// In local dev, the files service returns signed URLs rewritten to
	// localhost:4443 (for browser/curl on host). But the worker runs inside
	// Docker, where localhost points at the worker container, not the gcs
	// emulator container. Rewrite only for that special case.
	if u, err := url.Parse(signedURL); err == nil {
		if u.Host == "localhost:4443" || u.Host == "0.0.0.0:4443" || u.Host == "[::1]:4443" {
			u.Host = "gcs:4443"
			signedURL = u.String()
		}
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodDelete, signedURL, nil)
	if err != nil {
		return fmt.Errorf("failed to create delete request: %w", err)
	}

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("failed to execute delete request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		return fmt.Errorf("signed delete URL request returned status %d", resp.StatusCode)
	}

	return nil
}
