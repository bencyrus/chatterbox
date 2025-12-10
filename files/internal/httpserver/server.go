package httpserver

import (
	"encoding/json"
	"net/http"
	"net/url"
	"time"

	"github.com/bencyrus/chatterbox/files/internal/config"
	"github.com/bencyrus/chatterbox/files/internal/database"
	"github.com/bencyrus/chatterbox/files/internal/gcs"
	"github.com/bencyrus/chatterbox/shared/logger"
)

// Server holds dependencies for handling HTTP requests.
type Server struct {
	cfg config.Config
	db  *database.Client
}

// NewServer constructs a new HTTP server instance.
func NewServer(cfg config.Config, db *database.Client) *Server {
	return &Server{
		cfg: cfg,
		db:  db,
	}
}

// rewriteForEmulator rewrites a signed GCS URL to point at a local
// GCS-compatible emulator when running in a local environment.
// In non-local environments, or when no emulator URL is set,
// the original URL is returned unchanged.
func (s *Server) rewriteForEmulator(signedURL string) string {
	if s.cfg.Environment != "local" || s.cfg.GCSEmulatorURL == "" {
		return signedURL
	}

	base, err := url.Parse(s.cfg.GCSEmulatorURL)
	if err != nil {
		return signedURL
	}
	u, err := url.Parse(signedURL)
	if err != nil {
		return signedURL
	}

	u.Scheme = base.Scheme
	u.Host = base.Host
	return u.String()
}

// WithAPIKeyAuth wraps an http.Handler and enforces the FILE_SERVICE_API_KEY
// on all requests except health checks. This allows the service to be
// internet-accessible while still restricting sensitive endpoints to trusted
// callers such as the gateway.
func (s *Server) WithAPIKeyAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Allow unauthenticated access to health checks
		if r.URL.Path == "/healthz" {
			next.ServeHTTP(w, r)
			return
		}

		ctx := r.Context()
		providedKey := r.Header.Get("X-File-Service-Api-Key")
		if providedKey == "" || providedKey != s.cfg.FileServiceAPIKey {
			logger.Warn(ctx, "missing or invalid file service API key")
			http.Error(w, "forbidden", http.StatusForbidden)
			return
		}

		next.ServeHTTP(w, r)
	})
}

// HealthzHandler responds to health checks.
func (s *Server) HealthzHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	logger.Debug(ctx, "health check requested")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte("ok"))
}

// SignedDownloadURLHandler processes signed download URL requests for files.
func (s *Server) SignedDownloadURLHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	if r.Method != http.MethodPost {
		logger.Warn(ctx, "invalid method for signed_download_url endpoint", logger.Fields{
			"method": r.Method,
		})
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	w.Header().Set("Content-Type", "application/json")

	var body map[string]any
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		logger.Error(ctx, "failed to decode request body", err)
		http.Error(w, "invalid json", http.StatusBadRequest)
		return
	}

	arr, ok := body["files"]
	if !ok {
		logger.Warn(ctx, "missing files field in request")
		http.Error(w, "missing files", http.StatusBadRequest)
		return
	}

	items, ok := arr.([]any)
	if !ok {
		logger.Warn(ctx, "files field is not an array")
		http.Error(w, "files must be an array", http.StatusBadRequest)
		return
	}

	logger.Debug(ctx, "processing signed URL request", logger.Fields{
		"files_count": len(items),
	})

	// Convert file IDs from float64 (JSON numbers) to int64 for database lookup
	normalizedIDs := make([]int64, 0, len(items))
	for _, item := range items {
		if fileID, ok := item.(float64); ok {
			normalizedIDs = append(normalizedIDs, int64(fileID))
		}
	}

	if len(normalizedIDs) == 0 {
		logger.Debug(ctx, "no valid files to process after normalization")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("[]"))
		return
	}

	metadata, err := s.db.LookupFiles(ctx, normalizedIDs)
	if err != nil {
		logger.Error(ctx, "failed to lookup files in database", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}

	out := make([]map[string]any, 0, len(metadata))
	ttl := time.Duration(s.cfg.GCSSignedURLTTLSeconds) * time.Second

	for _, m := range metadata {
		url, err := gcs.SignedDownloadURL(s.cfg.GCSBucket, m.ObjectKey, s.cfg.GCSSigningEmail, s.cfg.GCSSigningPrivateKey, ttl)
		if err != nil {
			logger.Error(ctx, "failed to generate signed URL", err, logger.Fields{
				"file_id": m.FileID,
			})
			continue
		}
		out = append(out, map[string]any{
			"file_id": m.FileID,
			"url":     s.rewriteForEmulator(url),
		})
	}

	if len(out) == 0 {
		logger.Debug(ctx, "no signed URLs generated")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("[]"))
		return
	}

	logger.Info(ctx, "signed URLs generated successfully", logger.Fields{
		"processed_files": len(out),
	})

	enc := json.NewEncoder(w)
	if err := enc.Encode(out); err != nil {
		logger.Error(ctx, "failed to encode response", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
	}
}

// SignedDeleteURLHandler processes signed delete URL requests for files.
func (s *Server) SignedDeleteURLHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	if r.Method != http.MethodPost {
		logger.Warn(ctx, "invalid method for signed_delete_url endpoint", logger.Fields{
			"method": r.Method,
		})
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	w.Header().Set("Content-Type", "application/json")

	var body map[string]any
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		logger.Error(ctx, "failed to decode signed_delete_url request body", err)
		http.Error(w, "invalid json", http.StatusBadRequest)
		return
	}

	bucketRaw, ok := body["bucket"]
	if !ok {
		logger.Warn(ctx, "missing bucket field in signed_delete_url request")
		http.Error(w, "missing bucket", http.StatusBadRequest)
		return
	}
	objectKeyRaw, ok := body["object_key"]
	if !ok {
		logger.Warn(ctx, "missing object_key field in signed_delete_url request")
		http.Error(w, "missing object_key", http.StatusBadRequest)
		return
	}

	bucket, ok := bucketRaw.(string)
	if !ok || bucket == "" {
		logger.Warn(ctx, "bucket is not a non-empty string in signed_delete_url request")
		http.Error(w, "invalid bucket", http.StatusBadRequest)
		return
	}
	objectKey, ok := objectKeyRaw.(string)
	if !ok || objectKey == "" {
		logger.Warn(ctx, "object_key is not a non-empty string in signed_delete_url request")
		http.Error(w, "invalid object_key", http.StatusBadRequest)
		return
	}

	// Optional: validate that the requested bucket matches configured bucket.
	if bucket != s.cfg.GCSBucket {
		logger.Warn(ctx, "signed_delete_url bucket mismatch", logger.Fields{
			"requested_bucket":  bucket,
			"configured_bucket": s.cfg.GCSBucket,
		})
		http.Error(w, "invalid bucket", http.StatusBadRequest)
		return
	}

	ttl := time.Duration(s.cfg.GCSSignedURLTTLSeconds) * time.Second
	url, err := gcs.SignedDeleteURL(s.cfg.GCSBucket, objectKey, s.cfg.GCSSigningEmail, s.cfg.GCSSigningPrivateKey, ttl)
	if err != nil {
		logger.Error(ctx, "failed to generate signed delete URL", err, logger.Fields{
			"object_key": objectKey,
		})
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}

	logger.Info(ctx, "signed delete URL generated successfully", logger.Fields{
		"object_key": objectKey,
	})

	response := map[string]any{
		"url": s.rewriteForEmulator(url),
	}

	enc := json.NewEncoder(w)
	if err := enc.Encode(response); err != nil {
		logger.Error(ctx, "failed to encode signed_delete_url response", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
	}
}

// SignedUploadURLHandler processes signed upload URL requests for upload intents.
func (s *Server) SignedUploadURLHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	if r.Method != http.MethodPost {
		logger.Warn(ctx, "invalid method for signed_upload_url endpoint", logger.Fields{
			"method": r.Method,
		})
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	w.Header().Set("Content-Type", "application/json")

	var body map[string]any
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		logger.Error(ctx, "failed to decode request body", err)
		http.Error(w, "invalid json", http.StatusBadRequest)
		return
	}

	uploadIntentRaw, ok := body["upload_intent_id"]
	if !ok {
		logger.Warn(ctx, "missing upload_intent_id field in request")
		http.Error(w, "missing upload_intent_id", http.StatusBadRequest)
		return
	}

	logger.Debug(ctx, "processing signed upload URL request")

	// JSON numbers decode as float64 in Go
	uploadIntentID, ok := uploadIntentRaw.(float64)
	if !ok {
		logger.Warn(ctx, "upload_intent_id is not a number")
		http.Error(w, "invalid upload_intent_id", http.StatusBadRequest)
		return
	}

	intent, err := s.db.LookupUploadIntent(ctx, int64(uploadIntentID))
	if err != nil {
		logger.Error(ctx, "failed to lookup upload intent in database", err, logger.Fields{
			"upload_intent_id": int64(uploadIntentID),
		})
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}

	ttl := time.Duration(s.cfg.GCSSignedURLTTLSeconds) * time.Second
	url, err := gcs.SignedUploadURL(intent.Bucket, intent.ObjectKey, intent.MimeType, s.cfg.GCSSigningEmail, s.cfg.GCSSigningPrivateKey, ttl)
	if err != nil {
		logger.Error(ctx, "failed to generate signed upload URL", err, logger.Fields{
			"upload_intent_id": int64(uploadIntentID),
		})
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}

	logger.Info(ctx, "signed upload URL generated successfully", logger.Fields{
		"upload_intent_id": int64(uploadIntentID),
	})

	response := map[string]any{
		"upload_url": s.rewriteForEmulator(url),
	}

	enc := json.NewEncoder(w)
	if err := enc.Encode(response); err != nil {
		logger.Error(ctx, "failed to encode response", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
	}
}
