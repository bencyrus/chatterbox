package httpserver

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"cloud.google.com/go/storage"
	"github.com/bencyrus/chatterbox/files/internal/config"
	"github.com/bencyrus/chatterbox/files/internal/database"
	"github.com/bencyrus/chatterbox/files/internal/gcs"
	"github.com/bencyrus/chatterbox/files/internal/proxytoken"
	"github.com/bencyrus/chatterbox/shared/logger"
)

// Server holds dependencies for handling HTTP requests.
type Server struct {
	cfg    config.Config
	db     *database.Client
	data   *gcs.DataClient
	signer *proxytoken.Signer
}

// NewServer constructs a new HTTP server instance.
func NewServer(cfg config.Config, db *database.Client, data *gcs.DataClient, signer *proxytoken.Signer) *Server {
	return &Server{
		cfg:    cfg,
		db:     db,
		data:   data,
		signer: signer,
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

		// The streaming proxy endpoints are reached directly by end users and
		// are authorized by their short-lived HMAC token rather than the
		// internal API key. Exempt them from the API key requirement.
		if strings.HasPrefix(r.URL.Path, "/u/") || strings.HasPrefix(r.URL.Path, "/d/") {
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

	fileIDRaw, ok := body["file_id"]
	if !ok {
		logger.Warn(ctx, "missing file_id field in signed_delete_url request")
		http.Error(w, "missing file_id", http.StatusBadRequest)
		return
	}

	// JSON numbers decode as float64 in Go
	fileIDFloat, ok := fileIDRaw.(float64)
	if !ok {
		logger.Warn(ctx, "file_id is not a number in signed_delete_url request")
		http.Error(w, "invalid file_id", http.StatusBadRequest)
		return
	}
	fileID := int64(fileIDFloat)

	// Look up file metadata (bucket, object key) by ID so callers
	// don't need to know storage details.
	metadata, err := s.db.LookupFiles(ctx, []int64{fileID})
	if err != nil {
		logger.Error(ctx, "failed to lookup file for signed_delete_url", err, logger.Fields{
			"file_id": fileID,
		})
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	if len(metadata) == 0 {
		logger.Warn(ctx, "file not found for signed_delete_url", logger.Fields{
			"file_id": fileID,
		})
		http.Error(w, "file not found", http.StatusNotFound)
		return
	}

	m := metadata[0]

	// Optional: validate that the file's bucket matches configured bucket.
	if m.Bucket != s.cfg.GCSBucket {
		logger.Warn(ctx, "signed_delete_url bucket mismatch", logger.Fields{
			"file_id":           fileID,
			"file_bucket":       m.Bucket,
			"configured_bucket": s.cfg.GCSBucket,
		})
		http.Error(w, "invalid bucket", http.StatusBadRequest)
		return
	}

	ttl := time.Duration(s.cfg.GCSSignedURLTTLSeconds) * time.Second
	var deleteURL string

	// Local dev: fake-gcs-server does not support DELETE against the V4 signed
	// URL path style (/bucket/object). Instead, use its JSON API endpoint.
	if s.cfg.Environment == "local" && s.cfg.GCSEmulatorURL != "" {
		base, err := url.Parse(s.cfg.GCSEmulatorURL)
		if err != nil {
			http.Error(w, "invalid gcs emulator url", http.StatusInternalServerError)
			return
		}
		// Important: url.URL.Path should be the *decoded* path, and url.URL.RawPath
		// (when set) should contain the escaped form. If we put an already-escaped
		// string into Path, Go will escape '%' again, producing %252F.
		base.Path = fmt.Sprintf("/storage/v1/b/%s/o/%s", m.Bucket, m.ObjectKey)
		base.RawPath = fmt.Sprintf("/storage/v1/b/%s/o/%s", m.Bucket, url.PathEscape(m.ObjectKey))
		deleteURL = base.String()
	} else {
		signedURL, err := gcs.SignedDeleteURL(m.Bucket, m.ObjectKey, s.cfg.GCSSigningEmail, s.cfg.GCSSigningPrivateKey, ttl)
		if err != nil {
			logger.Error(ctx, "failed to generate signed delete URL", err, logger.Fields{
				"file_id":    fileID,
				"object_key": m.ObjectKey,
			})
			http.Error(w, "internal server error", http.StatusInternalServerError)
			return
		}
		deleteURL = s.rewriteForEmulator(signedURL)
	}

	logger.Info(ctx, "signed delete URL generated successfully", logger.Fields{
		"file_id":    fileID,
		"object_key": m.ObjectKey,
	})

	response := map[string]any{
		"url": deleteURL,
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

// ProxyUploadURLHandler mints a short-lived proxy upload URL for an upload
// intent. The returned URL points back at this service's streaming PUT endpoint
// instead of GCS, so clients upload through our servers. The response uses the
// same "upload_url" key the gateway already injects, keeping the client
// contract unchanged.
func (s *Server) ProxyUploadURLHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	if r.Method != http.MethodPost {
		logger.Warn(ctx, "invalid method for proxy_upload_url endpoint", logger.Fields{"method": r.Method})
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	w.Header().Set("Content-Type", "application/json")

	var body map[string]any
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		logger.Error(ctx, "failed to decode proxy_upload_url request body", err)
		http.Error(w, "invalid json", http.StatusBadRequest)
		return
	}

	uploadIntentRaw, ok := body["upload_intent_id"]
	if !ok {
		logger.Warn(ctx, "missing upload_intent_id field in proxy_upload_url request")
		http.Error(w, "missing upload_intent_id", http.StatusBadRequest)
		return
	}

	uploadIntentFloat, ok := uploadIntentRaw.(float64)
	if !ok {
		logger.Warn(ctx, "upload_intent_id is not a number in proxy_upload_url request")
		http.Error(w, "invalid upload_intent_id", http.StatusBadRequest)
		return
	}
	uploadIntentID := int64(uploadIntentFloat)

	// Verify the intent exists so we fail fast on bad ids.
	if _, err := s.db.LookupUploadIntent(ctx, uploadIntentID); err != nil {
		logger.Error(ctx, "failed to lookup upload intent for proxy_upload_url", err, logger.Fields{
			"upload_intent_id": uploadIntentID,
		})
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}

	ttl := time.Duration(s.cfg.GCSSignedURLTTLSeconds) * time.Second
	token := s.signer.Sign(proxytoken.OpPut, uploadIntentID, ttl)
	uploadURL := s.cfg.FilesPublicBaseURL + "/u/" + token

	logger.Info(ctx, "proxy upload URL generated successfully", logger.Fields{
		"upload_intent_id": uploadIntentID,
	})

	response := map[string]any{"upload_url": uploadURL}
	if err := json.NewEncoder(w).Encode(response); err != nil {
		logger.Error(ctx, "failed to encode proxy_upload_url response", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
	}
}

// ProxyDownloadURLHandler mints short-lived proxy download URLs for a list of
// file ids. The returned URLs point back at this service's streaming GET
// endpoint instead of GCS. The response shape matches /signed_download_url so
// the gateway can inject it under "processed_files" unchanged.
func (s *Server) ProxyDownloadURLHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	if r.Method != http.MethodPost {
		logger.Warn(ctx, "invalid method for proxy_download_url endpoint", logger.Fields{"method": r.Method})
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	w.Header().Set("Content-Type", "application/json")

	var body map[string]any
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		logger.Error(ctx, "failed to decode proxy_download_url request body", err)
		http.Error(w, "invalid json", http.StatusBadRequest)
		return
	}

	arr, ok := body["files"]
	if !ok {
		logger.Warn(ctx, "missing files field in proxy_download_url request")
		http.Error(w, "missing files", http.StatusBadRequest)
		return
	}

	items, ok := arr.([]any)
	if !ok {
		logger.Warn(ctx, "files field is not an array in proxy_download_url request")
		http.Error(w, "files must be an array", http.StatusBadRequest)
		return
	}

	normalizedIDs := make([]int64, 0, len(items))
	for _, item := range items {
		if fileID, ok := item.(float64); ok {
			normalizedIDs = append(normalizedIDs, int64(fileID))
		}
	}

	if len(normalizedIDs) == 0 {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("[]"))
		return
	}

	// Only mint URLs for files that actually exist, matching the behavior of
	// /signed_download_url.
	metadata, err := s.db.LookupFiles(ctx, normalizedIDs)
	if err != nil {
		logger.Error(ctx, "failed to lookup files for proxy_download_url", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}

	ttl := time.Duration(s.cfg.GCSSignedURLTTLSeconds) * time.Second
	out := make([]map[string]any, 0, len(metadata))
	for _, m := range metadata {
		token := s.signer.Sign(proxytoken.OpGet, m.FileID, ttl)
		out = append(out, map[string]any{
			"file_id": m.FileID,
			"url":     s.cfg.FilesPublicBaseURL + "/d/" + token,
		})
	}

	if len(out) == 0 {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("[]"))
		return
	}

	logger.Info(ctx, "proxy download URLs generated successfully", logger.Fields{
		"processed_files": len(out),
	})

	if err := json.NewEncoder(w).Encode(out); err != nil {
		logger.Error(ctx, "failed to encode proxy_download_url response", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
	}
}

// setProxyCORSHeaders sets permissive CORS headers required for the web client
// to upload/stream cross-origin (chatterboxtalk.com -> files.chatterboxtalk.com).
func (s *Server) setProxyCORSHeaders(w http.ResponseWriter) {
	h := w.Header()
	h.Set("Access-Control-Allow-Origin", "*")
	h.Set("Access-Control-Allow-Methods", "PUT, GET, HEAD, OPTIONS")
	h.Set("Access-Control-Allow-Headers", "Content-Type")
	h.Set("Access-Control-Expose-Headers", "Content-Range, Accept-Ranges, Content-Length, Content-Type")
}

// UploadProxyHandler streams a client upload (PUT /u/{token}) through to GCS.
// Authorization is provided by the HMAC token, not the internal API key.
func (s *Server) UploadProxyHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	s.setProxyCORSHeaders(w)

	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	if r.Method != http.MethodPut {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	token := strings.TrimPrefix(r.URL.Path, "/u/")
	if token == "" {
		http.Error(w, "missing token", http.StatusBadRequest)
		return
	}

	uploadIntentID, err := s.signer.Verify(token, proxytoken.OpPut)
	if err != nil {
		logger.Warn(ctx, "invalid upload proxy token", logger.Fields{"error": err.Error()})
		http.Error(w, "forbidden", http.StatusForbidden)
		return
	}

	intent, err := s.db.LookupUploadIntent(ctx, uploadIntentID)
	if err != nil {
		logger.Error(ctx, "failed to lookup upload intent for upload proxy", err, logger.Fields{
			"upload_intent_id": uploadIntentID,
		})
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}

	defer r.Body.Close()
	n, err := s.data.UploadStream(ctx, intent.Bucket, intent.ObjectKey, intent.MimeType, r.Body)
	if err != nil {
		logger.Error(ctx, "failed to stream upload to GCS", err, logger.Fields{
			"upload_intent_id": uploadIntentID,
		})
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}

	logger.Info(ctx, "upload proxied to GCS", logger.Fields{
		"upload_intent_id": uploadIntentID,
		"bytes":            n,
	})
	w.WriteHeader(http.StatusOK)
}

// DownloadProxyHandler streams an object from GCS back to the client
// (GET/HEAD /d/{token}), honoring HTTP Range requests so audio players can seek.
func (s *Server) DownloadProxyHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	s.setProxyCORSHeaders(w)

	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	token := strings.TrimPrefix(r.URL.Path, "/d/")
	if token == "" {
		http.Error(w, "missing token", http.StatusBadRequest)
		return
	}

	fileID, err := s.signer.Verify(token, proxytoken.OpGet)
	if err != nil {
		logger.Warn(ctx, "invalid download proxy token", logger.Fields{"error": err.Error()})
		http.Error(w, "forbidden", http.StatusForbidden)
		return
	}

	metadata, err := s.db.LookupFiles(ctx, []int64{fileID})
	if err != nil {
		logger.Error(ctx, "failed to lookup file for download proxy", err, logger.Fields{"file_id": fileID})
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	if len(metadata) == 0 {
		http.Error(w, "file not found", http.StatusNotFound)
		return
	}
	m := metadata[0]

	offset, length, isRange, err := parseRangeHeader(r.Header.Get("Range"))
	if err != nil {
		http.Error(w, "invalid range", http.StatusRequestedRangeNotSatisfiable)
		return
	}

	var reader *storage.Reader
	if isRange {
		reader, err = s.data.NewRangeReader(ctx, m.Bucket, m.ObjectKey, offset, length)
	} else {
		reader, err = s.data.NewRangeReader(ctx, m.Bucket, m.ObjectKey, 0, -1)
	}
	if err != nil {
		logger.Error(ctx, "failed to open GCS reader for download proxy", err, logger.Fields{"file_id": fileID})
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	defer reader.Close()

	totalSize := reader.Attrs.Size
	contentType := reader.Attrs.ContentType
	if contentType == "" {
		contentType = m.MimeType
	}
	w.Header().Set("Content-Type", contentType)
	w.Header().Set("Accept-Ranges", "bytes")

	if isRange {
		remain := reader.Remain()
		start := offset
		if offset < 0 {
			// Suffix range (bytes=-N): compute the real start from the end.
			start = totalSize + offset
			if start < 0 {
				start = 0
			}
		}
		end := start + remain - 1
		w.Header().Set("Content-Range", fmt.Sprintf("bytes %d-%d/%d", start, end, totalSize))
		w.Header().Set("Content-Length", strconv.FormatInt(remain, 10))
		w.WriteHeader(http.StatusPartialContent)
	} else {
		w.Header().Set("Content-Length", strconv.FormatInt(totalSize, 10))
		w.WriteHeader(http.StatusOK)
	}

	if r.Method == http.MethodHead {
		return
	}

	if _, err := io.Copy(w, reader); err != nil {
		logger.Warn(ctx, "error streaming download proxy body", logger.Fields{
			"file_id": fileID,
			"error":   err.Error(),
		})
	}
}

// parseRangeHeader parses a single HTTP byte range. Supported forms:
//
//	bytes=START-END
//	bytes=START-
//	bytes=-SUFFIX
//
// It returns offset/length suitable for storage.NewRangeReader. For a suffix
// range (bytes=-N) offset is negative and length is -1. When no Range header is
// present, isRange is false.
func parseRangeHeader(header string) (offset, length int64, isRange bool, err error) {
	if header == "" {
		return 0, -1, false, nil
	}
	if !strings.HasPrefix(header, "bytes=") {
		return 0, 0, false, fmt.Errorf("unsupported range unit")
	}

	spec := strings.TrimPrefix(header, "bytes=")
	if strings.Contains(spec, ",") {
		return 0, 0, false, fmt.Errorf("multiple ranges not supported")
	}

	dash := strings.IndexByte(spec, '-')
	if dash < 0 {
		return 0, 0, false, fmt.Errorf("invalid range")
	}

	startStr := strings.TrimSpace(spec[:dash])
	endStr := strings.TrimSpace(spec[dash+1:])

	if startStr == "" {
		// Suffix range: bytes=-N -> last N bytes.
		n, perr := strconv.ParseInt(endStr, 10, 64)
		if perr != nil || n <= 0 {
			return 0, 0, false, fmt.Errorf("invalid suffix range")
		}
		return -n, -1, true, nil
	}

	start, perr := strconv.ParseInt(startStr, 10, 64)
	if perr != nil || start < 0 {
		return 0, 0, false, fmt.Errorf("invalid range start")
	}

	if endStr == "" {
		// bytes=START- -> from start to end of object.
		return start, -1, true, nil
	}

	end, perr := strconv.ParseInt(endStr, 10, 64)
	if perr != nil || end < start {
		return 0, 0, false, fmt.Errorf("invalid range end")
	}
	return start, end - start + 1, true, nil
}
