package openai

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"time"

	"github.com/bencyrus/chatterbox/shared/logger"
	"github.com/bencyrus/chatterbox/worker/internal/types"
)

const responsesAPIURL = "https://api.openai.com/v1/responses"

type Service struct {
	apiKey     string
	httpClient *http.Client
}

func NewService(apiKey string) *Service {
	return &Service{
		apiKey: apiKey,
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
	}
}

// CreateResponse starts a background OpenAI Responses API call.
func (s *Service) CreateResponse(
	ctx context.Context,
	payload *types.OpenAIResponseCreatePayload,
) (*types.OpenAIResponseCreateResult, error) {
	if payload == nil {
		return nil, fmt.Errorf("openai response create payload is nil")
	}
	if s.apiKey == "" {
		return nil, fmt.Errorf("OpenAI API key is not configured")
	}
	if len(payload.RequestBody) == 0 || !json.Valid(payload.RequestBody) {
		return nil, fmt.Errorf("OpenAI response create request_body must be valid JSON")
	}

	logger.Info(ctx, "calling OpenAI Responses API", logger.Fields{
		"attempt_id": payload.OpenAIResponseAttemptID,
	})

	req, err := http.NewRequestWithContext(
		ctx,
		http.MethodPost,
		responsesAPIURL,
		bytes.NewReader(payload.RequestBody),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create OpenAI response request: %w", err)
	}

	req.Header.Set("Authorization", "Bearer "+s.apiKey)
	req.Header.Set("Content-Type", "application/json")

	body, err := s.do(req)
	if err != nil {
		return nil, err
	}

	var envelope struct {
		ID     string `json:"id"`
		Status string `json:"status"`
	}
	if err := json.Unmarshal(body, &envelope); err != nil {
		return nil, fmt.Errorf("failed to parse OpenAI response create body: %w", err)
	}
	if envelope.ID == "" {
		return nil, fmt.Errorf("OpenAI response create body missing id")
	}

	logger.Info(ctx, "OpenAI response created", logger.Fields{
		"attempt_id":         payload.OpenAIResponseAttemptID,
		"openai_response_id": envelope.ID,
		"status":             envelope.Status,
	})

	return &types.OpenAIResponseCreateResult{
		OpenAIResponseID: envelope.ID,
		Status:           envelope.Status,
		ResponseBody:     json.RawMessage(append([]byte(nil), body...)),
	}, nil
}

// RetrieveResponse fetches the canonical response body by response id.
func (s *Service) RetrieveResponse(
	ctx context.Context,
	payload *types.OpenAIResponseRetrievePayload,
) (*types.OpenAIResponseRetrieveResult, error) {
	if payload == nil {
		return nil, fmt.Errorf("openai response retrieve payload is nil")
	}
	if s.apiKey == "" {
		return nil, fmt.Errorf("OpenAI API key is not configured")
	}
	if payload.OpenAIResponseID == "" {
		return nil, fmt.Errorf("OpenAI response retrieve payload missing openai_response_id")
	}

	logger.Info(ctx, "retrieving OpenAI response", logger.Fields{
		"attempt_id":         payload.OpenAIResponseAttemptID,
		"openai_response_id": payload.OpenAIResponseID,
	})

	req, err := http.NewRequestWithContext(
		ctx,
		http.MethodGet,
		responsesAPIURL+"/"+url.PathEscape(payload.OpenAIResponseID),
		nil,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create OpenAI response retrieve request: %w", err)
	}

	req.Header.Set("Authorization", "Bearer "+s.apiKey)

	body, err := s.do(req)
	if err != nil {
		return nil, err
	}

	var envelope struct {
		ID     string `json:"id"`
		Status string `json:"status"`
	}
	if err := json.Unmarshal(body, &envelope); err != nil {
		return nil, fmt.Errorf("failed to parse OpenAI response retrieve body: %w", err)
	}
	if envelope.ID == "" {
		return nil, fmt.Errorf("OpenAI response retrieve body missing id")
	}

	logger.Info(ctx, "OpenAI response retrieved", logger.Fields{
		"attempt_id":         payload.OpenAIResponseAttemptID,
		"openai_response_id": envelope.ID,
		"status":             envelope.Status,
	})

	return &types.OpenAIResponseRetrieveResult{
		OpenAIResponseID: envelope.ID,
		Status:           envelope.Status,
		ResponseBody:     json.RawMessage(append([]byte(nil), body...)),
	}, nil
}

func (s *Service) do(req *http.Request) ([]byte, error) {
	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("OpenAI API request failed: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read OpenAI API response body: %w", err)
	}

	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("OpenAI API returned %d: %s", resp.StatusCode, string(body))
	}

	return body, nil
}
