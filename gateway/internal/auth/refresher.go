package auth

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"

	"github.com/bencyrus/chatterbox/gateway/internal/config"
)

type RefreshResult struct {
	AccessToken  string
	RefreshToken string
}

// RefreshIfPresent attempts to refresh tokens using the provided refresh token header.
// If no refresh token header is present, it returns nil result and nil error.
// Any refresh error is returned, but callers may choose to ignore it.
func RefreshIfPresent(ctx context.Context, cfg config.Config, requestHeaders http.Header) (*RefreshResult, error) {
	refreshToken := requestHeaders.Get(cfg.RefreshTokenHeaderIn)
	if refreshToken == "" {
		return nil, nil
	}

	payload := map[string]string{"refresh_token": refreshToken}
	body, _ := json.Marshal(payload)

	client := &http.Client{Timeout: time.Duration(cfg.HTTPClientTimeoutSeconds) * time.Second}
	url := cfg.PostgRESTURL + cfg.RefreshTokensPath
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	bodyBytes, readErr := io.ReadAll(resp.Body)
	if readErr != nil {
		return nil, fmt.Errorf("failed to read refresh response body: %w", readErr)
	}

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("refresh failed: status %d body: %s", resp.StatusCode, string(bodyBytes))
	}

	var parsed struct {
		AccessToken  string `json:"access_token"`
		RefreshToken string `json:"refresh_token"`
	}
	if err := json.Unmarshal(bodyBytes, &parsed); err != nil {
		return nil, err
	}
	if parsed.AccessToken == "" || parsed.RefreshToken == "" {
		return nil, fmt.Errorf("refresh response missing tokens")
	}

	return &RefreshResult{AccessToken: parsed.AccessToken, RefreshToken: parsed.RefreshToken}, nil
}
