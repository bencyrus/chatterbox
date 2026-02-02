package types

// TranscriptionKickoffPayload represents the payload structure for transcription_kickoff
// tasks after being prepared by the before_handler in Postgres.
// It is built by learning.get_recording_transcription_kickoff_payload(payload jsonb).
type TranscriptionKickoffPayload struct {
	FileID                          int64 `json:"file_id"`
	RecordingTranscriptionAttemptID int64 `json:"recording_transcription_attempt_id"`
}

// TranscriptionKickoffResult represents the result returned from the worker
// after successfully kicking off a transcription request to ElevenLabs.
// The RequestID is the ElevenLabs request_id returned from the async API call.
type TranscriptionKickoffResult struct {
	RequestID string `json:"request_id"`
}

// ElevenLabsAsyncResponse represents the response from ElevenLabs when
// calling the speech-to-text API with webhook=true.
type ElevenLabsAsyncResponse struct {
	RequestID string `json:"request_id"`
}
