package files

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"time"

	"github.com/bencyrus/chatterbox/gateway/internal/config"
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

	client := &http.Client{Timeout: time.Duration(cfg.HTTPClientTimeoutSeconds) * time.Second}
	url := cfg.FileServiceURL + cfg.FileSignedURLPath
	payload := map[string]any{"files": filesSlice}
	reqBody, _ := json.Marshal(payload)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(reqBody))
	if err != nil {
		return body, nil
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		return body, nil
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return body, nil
	}

	var serviceJSON any
	if err := json.NewDecoder(resp.Body).Decode(&serviceJSON); err != nil {
		return body, nil
	}

	generic[cfg.ProcessedFilesFieldName] = serviceJSON
	newBody, err := json.Marshal(generic)
	if err != nil {
		return body, nil
	}
	return newBody, nil
}
