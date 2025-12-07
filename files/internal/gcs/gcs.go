package gcs

import (
	"strings"
	"time"

	"cloud.google.com/go/storage"
)

// SignedDownloadURL generates a V4 signed URL for downloading an object from GCS.
func SignedDownloadURL(bucket, objectKey, serviceAccountEmail, privateKey string, ttl time.Duration) (string, error) {
	// Convert literal \n sequences back into real newlines for the private key.
	key := strings.ReplaceAll(privateKey, `\n`, "\n")

	return storage.SignedURL(bucket, objectKey, &storage.SignedURLOptions{
		Scheme:         storage.SigningSchemeV4,
		Method:         "GET",
		Expires:        time.Now().Add(ttl),
		GoogleAccessID: serviceAccountEmail,
		PrivateKey:     []byte(key),
	})
}
