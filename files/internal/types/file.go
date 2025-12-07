package types

// FileMetadata represents basic file information returned from the database.
type FileMetadata struct {
	FileID    int64  `json:"file_id"`
	Bucket    string `json:"bucket"`
	ObjectKey string `json:"object_key"`
	MimeType  string `json:"mime_type"`
}

// UploadIntentMetadata represents upload intent information from the database.
type UploadIntentMetadata struct {
	UploadIntentID int64  `json:"upload_intent_id"`
	Bucket         string `json:"bucket"`
	ObjectKey      string `json:"object_key"`
	MimeType       string `json:"mime_type"`
}
