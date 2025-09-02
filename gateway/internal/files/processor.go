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
	// Case 1: top-level object { ..., files: [...] }
	var asObject map[string]any
	if err := json.Unmarshal(body, &asObject); err == nil {
		if filesRaw, ok := asObject[cfg.FilesFieldName]; ok {
			filesSlice, ok := filesRaw.([]any)
			if !ok || len(filesSlice) == 0 {
				return body, nil
			}

			client := &http.Client{Timeout: time.Duration(cfg.HTTPClientTimeoutSeconds) * time.Second}
			url := cfg.FileServiceURL + cfg.FileSignedURLPath
			reqBody, err := json.Marshal(map[string]any{"files": filesSlice})
			if err != nil {
				return body, nil
			}
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
			var signed any
			if err := json.NewDecoder(resp.Body).Decode(&signed); err != nil {
				return body, nil
			}
			asObject[cfg.ProcessedFilesFieldName] = signed
			b, err := json.Marshal(asObject)
			if err != nil {
				return body, nil
			}
			return b, nil
		}
	}

	// Case 2: top-level array [ { files: [...] }, ... ]
	var asArray []any
	if err := json.Unmarshal(body, &asArray); err != nil {
		return body, nil
	}
	modified := false
	for i, item := range asArray {
		obj, ok := item.(map[string]any)
		if !ok {
			continue
		}
		filesRaw, ok := obj[cfg.FilesFieldName]
		if !ok {
			continue
		}
		filesSlice, ok := filesRaw.([]any)
		if !ok || len(filesSlice) == 0 {
			continue
		}

		client := &http.Client{Timeout: time.Duration(cfg.HTTPClientTimeoutSeconds) * time.Second}
		url := cfg.FileServiceURL + cfg.FileSignedURLPath
		reqBody, err := json.Marshal(map[string]any{"files": filesSlice})
		if err != nil {
			continue
		}
		req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(reqBody))
		if err != nil {
			continue
		}
		req.Header.Set("Content-Type", "application/json")
		resp, err := client.Do(req)
		if err != nil {
			continue
		}
		if resp.StatusCode < 200 || resp.StatusCode >= 300 {
			resp.Body.Close()
			continue
		}
		var signed any
		if err := json.NewDecoder(resp.Body).Decode(&signed); err != nil {
			resp.Body.Close()
			continue
		}
		resp.Body.Close()
		obj[cfg.ProcessedFilesFieldName] = signed
		asArray[i] = obj
		modified = true
	}
	if !modified {
		return body, nil
	}
	b, err := json.Marshal(asArray)
	if err != nil {
		return body, nil
	}
	return b, nil
}
