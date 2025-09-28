package email

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/bencyrus/chatterbox/shared/logger"
	"github.com/bencyrus/chatterbox/worker/internal/types"
)

type Service struct {
	apiKey     string
	httpClient *http.Client
}

type ResendRequest struct {
	From    string   `json:"from"`
	To      []string `json:"to"`
	Subject string   `json:"subject"`
	HTML    string   `json:"html"`
}

type ResendResponse struct {
	ID    string `json:"id"`
	Error string `json:"error,omitempty"`
}

func NewService(apiKey string) *Service {
	return &Service{
		apiKey: apiKey,
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
	}
}

// SendEmail sends an email using the Resend API
func (s *Service) SendEmail(ctx context.Context, payload *types.EmailPayload) (*ResendResponse, error) {
	if payload == nil {
		return nil, fmt.Errorf("email payload is nil")
	}

	logger.Info(ctx, "sending email", logger.Fields{
		"message_id":   payload.MessageID,
		"to_address":   payload.ToAddress,
		"from_address": payload.FromAddress,
		"subject":      payload.Subject,
	})

	// Build Resend request
	resendReq := ResendRequest{
		From:    payload.FromAddress,
		To:      []string{payload.ToAddress},
		Subject: payload.Subject,
		HTML:    payload.HTML,
	}

	// Marshal request body
	reqBody, err := json.Marshal(resendReq)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal resend request: %w", err)
	}

	// Create HTTP request
	req, err := http.NewRequestWithContext(ctx, "POST", "https://api.resend.com/emails", bytes.NewReader(reqBody))
	if err != nil {
		return nil, fmt.Errorf("failed to create HTTP request: %w", err)
	}

	req.Header.Set("Authorization", "Bearer "+s.apiKey)
	req.Header.Set("Content-Type", "application/json")

	// Send request
	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to send HTTP request: %w", err)
	}
	defer resp.Body.Close()

	// Parse response
	var resendResp ResendResponse
	if err := json.NewDecoder(resp.Body).Decode(&resendResp); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	// Check for API errors
	if resp.StatusCode >= 400 {
		errMsg := fmt.Sprintf("resend API error (status %d)", resp.StatusCode)
		if resendResp.Error != "" {
			errMsg += ": " + resendResp.Error
		}
		return nil, fmt.Errorf(errMsg)
	}

	logger.Info(ctx, "email sent successfully", logger.Fields{
		"message_id": payload.MessageID,
		"resend_id":  resendResp.ID,
	})

	return &resendResp, nil
}
