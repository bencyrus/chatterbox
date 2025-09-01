package auth

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log"
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
	log.Println("refreshToken", refreshToken)
	if refreshToken == "" {
		log.Println("no refresh token")
		return nil, nil
	}

	payload := map[string]string{"refresh_token": refreshToken}
	log.Println("payload", payload)
	body, _ := json.Marshal(payload)
	log.Println("body", string(body))

	client := &http.Client{Timeout: time.Duration(cfg.HTTPClientTimeoutSeconds) * time.Second}
	url := cfg.PostgRESTURL + cfg.RefreshTokensPath
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := client.Do(req)
	log.Println("resp", resp)
	if err != nil {
		log.Println("error", err)
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		log.Println("refresh failed: status", resp.StatusCode)
		return nil, fmt.Errorf("refresh failed: status %d", resp.StatusCode)
	}

	var parsed struct {
		AccessToken  string `json:"access_token"`
		RefreshToken string `json:"refresh_token"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&parsed); err != nil {
		log.Println("error", err)
		return nil, err
	}
	if parsed.AccessToken == "" || parsed.RefreshToken == "" {
		log.Println("refresh response missing tokens")
		return nil, fmt.Errorf("refresh response missing tokens")
	}

	return &RefreshResult{AccessToken: parsed.AccessToken, RefreshToken: parsed.RefreshToken}, nil
}
