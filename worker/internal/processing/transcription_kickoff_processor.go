package processing

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"time"

	"github.com/bencyrus/chatterbox/shared/logger"
	"github.com/bencyrus/chatterbox/worker/internal/services/files"
	"github.com/bencyrus/chatterbox/worker/internal/types"
)

const (
	elevenLabsAPIURL = "https://api.elevenlabs.io/v1/speech-to-text"
	elevenLabsModel  = "scribe_v2"
)

// TranscriptionKickoffProcessor handles task_type == "transcription_kickoff" by:
// - Calling the before_handler to get the file_id and attempt_id
// - Requesting a signed download URL from the files service
// - Calling the ElevenLabs speech-to-text API with webhook=true
// - Returning the request_id for the success handler to record
// Success and error facts are recorded via the standard handler flow.
type TranscriptionKickoffProcessor struct {
	handlers      *HandlerInvoker
	filesService  *files.Service
	elevenLabsKey string
	httpClient    *http.Client
}

// NewTranscriptionKickoffProcessor creates a new TranscriptionKickoffProcessor.
func NewTranscriptionKickoffProcessor(
	handlers *HandlerInvoker,
	filesService *files.Service,
	elevenLabsKey string,
) *TranscriptionKickoffProcessor {
	return &TranscriptionKickoffProcessor{
		handlers:      handlers,
		filesService:  filesService,
		elevenLabsKey: elevenLabsKey,
		httpClient: &http.Client{
			Timeout: 30 * time.Second, // Short timeout - just kickoff, not waiting for result
		},
	}
}

func (p *TranscriptionKickoffProcessor) TaskType() string  { return "transcription_kickoff" }
func (p *TranscriptionKickoffProcessor) HasHandlers() bool { return true }

func (p *TranscriptionKickoffProcessor) Process(ctx context.Context, task *types.Task) *types.TaskResult {
	var payload types.TaskPayload
	if err := json.Unmarshal(task.Payload, &payload); err != nil {
		return types.NewTaskFailure(fmt.Errorf("failed to unmarshal task payload: %w", err))
	}
	if payload.BeforeHandler == "" {
		return types.NewTaskFailure(fmt.Errorf("transcription_kickoff task missing before_handler"))
	}

	// Get file details and attempt ID from before_handler
	var kickoffPayload types.TranscriptionKickoffPayload
	if err := p.handlers.CallBefore(ctx, payload.BeforeHandler, task.Payload, &kickoffPayload); err != nil {
		return types.NewTaskFailure(fmt.Errorf("transcription_kickoff before_handler failed: %w", err))
	}

	logger.Info(ctx, "processing transcription_kickoff task", logger.Fields{
		"file_id":    kickoffPayload.FileID,
		"attempt_id": kickoffPayload.RecordingTranscriptionAttemptID,
	})

	// Get signed download URL from files service
	signedURL, err := p.filesService.GetSignedDownloadURL(ctx, kickoffPayload.FileID)
	if err != nil {
		return types.NewTaskFailure(fmt.Errorf("failed to get signed download URL: %w", err))
	}

	logger.Info(ctx, "obtained signed download URL", logger.Fields{
		"file_id": kickoffPayload.FileID,
	})

	// Call ElevenLabs API with webhook=true
	result, err := p.callElevenLabsAsync(ctx, signedURL, kickoffPayload.RecordingTranscriptionAttemptID)
	if err != nil {
		return types.NewTaskFailure(fmt.Errorf("ElevenLabs API error: %w", err))
	}

	logger.Info(ctx, "transcription kicked off successfully", logger.Fields{
		"request_id": result.RequestID,
		"attempt_id": kickoffPayload.RecordingTranscriptionAttemptID,
	})

	return types.NewTaskSuccess(&types.TranscriptionKickoffResult{
		RequestID: result.RequestID,
	})
}

// callElevenLabsAsync calls the ElevenLabs speech-to-text API with webhook=true.
// It uses multipart/form-data as required by the API.
func (p *TranscriptionKickoffProcessor) callElevenLabsAsync(
	ctx context.Context,
	audioURL string,
	attemptID int64,
) (*types.ElevenLabsAsyncResponse, error) {
	if p.elevenLabsKey == "" {
		return nil, fmt.Errorf("ElevenLabs API key is not configured")
	}

	var buf bytes.Buffer
	writer := multipart.NewWriter(&buf)

	// Required fields
	if err := writer.WriteField("model_id", elevenLabsModel); err != nil {
		return nil, fmt.Errorf("failed to write model_id: %w", err)
	}

	if err := writer.WriteField("cloud_storage_url", audioURL); err != nil {
		return nil, fmt.Errorf("failed to write cloud_storage_url: %w", err)
	}

	// Enable webhook mode
	if err := writer.WriteField("webhook", "true"); err != nil {
		return nil, fmt.Errorf("failed to write webhook: %w", err)
	}

	// Include attempt ID in webhook metadata for correlation
	webhookMetadata, err := json.Marshal(map[string]int64{
		"recording_transcription_attempt_id": attemptID,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to marshal webhook metadata: %w", err)
	}
	if err := writer.WriteField("webhook_metadata", string(webhookMetadata)); err != nil {
		return nil, fmt.Errorf("failed to write webhook_metadata: %w", err)
	}

	// Optional settings for better transcription
	if err := writer.WriteField("tag_audio_events", "true"); err != nil {
		return nil, fmt.Errorf("failed to write tag_audio_events: %w", err)
	}

	if err := writer.WriteField("timestamps_granularity", "word"); err != nil {
		return nil, fmt.Errorf("failed to write timestamps_granularity: %w", err)
	}

	if err := writer.Close(); err != nil {
		return nil, fmt.Errorf("failed to close multipart writer: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, elevenLabsAPIURL, &buf)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", writer.FormDataContentType())
	req.Header.Set("xi-api-key", p.elevenLabsKey)

	logger.Info(ctx, "calling ElevenLabs speech-to-text API", logger.Fields{
		"model": elevenLabsModel,
	})

	resp, err := p.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response body: %w", err)
	}

	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("API returned %d: %s", resp.StatusCode, string(body))
	}

	var result types.ElevenLabsAsyncResponse
	if err := json.Unmarshal(body, &result); err != nil {
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}

	if result.RequestID == "" {
		return nil, fmt.Errorf("ElevenLabs response missing request_id")
	}

	return &result, nil
}
