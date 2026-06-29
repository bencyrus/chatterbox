package gcs

import (
	"context"
	"fmt"
	"io"
	"strings"

	"cloud.google.com/go/storage"
	"google.golang.org/api/option"
)

// DataClient wraps a GCS storage client for server-side streaming of object
// bytes (upload and download), as opposed to the signing-only helpers in
// gcs.go. It is used by the proxy endpoints so that clients never talk to GCS
// directly.
type DataClient struct {
	client *storage.Client
}

// NewDataClient constructs a GCS data client. When emulatorHost is non-empty the
// client talks to a GCS-compatible emulator (e.g. fake-gcs-server) without
// authentication; otherwise it authenticates using the provided service account
// email and private key, mirroring the credential assembly used by db-backup.
//
// Note: the official storage client also reads the STORAGE_EMULATOR_HOST
// environment variable to determine the emulator endpoint, so that variable must
// be present in the environment for emulator usage.
func NewDataClient(ctx context.Context, serviceAccountEmail, privateKey, emulatorHost string) (*DataClient, error) {
	var opts []option.ClientOption

	if emulatorHost != "" {
		opts = append(opts, option.WithoutAuthentication())
	} else {
		// Convert literal \n sequences back into real newlines for the private key.
		key := strings.ReplaceAll(privateKey, `\n`, "\n")

		// Build credentials JSON from the service account email and private key.
		credJSON := fmt.Sprintf(`{
  "type": "service_account",
  "client_email": "%s",
  "private_key": "%s",
  "token_uri": "https://oauth2.googleapis.com/token"
}`, serviceAccountEmail, strings.ReplaceAll(key, "\n", "\\n"))

		opts = append(opts, option.WithCredentialsJSON([]byte(credJSON)))
	}

	client, err := storage.NewClient(ctx, opts...)
	if err != nil {
		return nil, fmt.Errorf("failed to create GCS data client: %w", err)
	}

	return &DataClient{client: client}, nil
}

// Close releases the underlying storage client.
func (c *DataClient) Close() error {
	return c.client.Close()
}

// UploadStream streams the contents of r into the given bucket/object, setting
// the provided content type. It does not buffer the entire body in memory.
func (c *DataClient) UploadStream(ctx context.Context, bucket, objectKey, contentType string, r io.Reader) (int64, error) {
	obj := c.client.Bucket(bucket).Object(objectKey)
	w := obj.NewWriter(ctx)
	if contentType != "" {
		w.ContentType = contentType
	}

	n, err := io.Copy(w, r)
	if err != nil {
		// Best-effort close to release resources; the upload is already failed.
		_ = w.Close()
		return n, fmt.Errorf("failed to stream object to GCS: %w", err)
	}

	if err := w.Close(); err != nil {
		return n, fmt.Errorf("failed to finalize GCS upload: %w", err)
	}

	return n, nil
}

// NewRangeReader returns a reader for a byte range of the object. A length of -1
// reads to the end of the object. The returned *storage.Reader exposes the total
// object size and content type via its Attrs field. The caller must Close it.
func (c *DataClient) NewRangeReader(ctx context.Context, bucket, objectKey string, offset, length int64) (*storage.Reader, error) {
	obj := c.client.Bucket(bucket).Object(objectKey)
	reader, err := obj.NewRangeReader(ctx, offset, length)
	if err != nil {
		return nil, fmt.Errorf("failed to open GCS range reader: %w", err)
	}
	return reader, nil
}
