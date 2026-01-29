package types

// FileDeletePayload represents the payload structure for file_delete tasks
// after being prepared by the before_handler in Postgres.
// It is built by files.get_file_deletion_payload(payload jsonb) and intentionally
// only exposes the file ID so the worker remains unaware of storage details.
type FileDeletePayload struct {
	FileID int64 `json:"file_id"`
}

// FileDeleteResult represents basic observability data returned from the
// worker after attempting a file deletion via the files service.
// It mirrors the minimal information needed by downstream handlers.
type FileDeleteResult struct {
	FileID          int64  `json:"file_id"`
	DeleteStatus    string `json:"delete_status,omitempty"`
	SignedDeleteURL string `json:"signed_delete_url,omitempty"`
}

// FileSignedDeleteURLResponse represents the HTTP response body returned by
// the files service /signed_delete_url endpoint.
type FileSignedDeleteURLResponse struct {
	URL string `json:"url"`
}
