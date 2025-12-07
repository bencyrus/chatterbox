package files

import (
	"bytes"
	"context"
	"io"
	"net/http"
	"strconv"
	"strings"

	"github.com/bencyrus/chatterbox/gateway/internal/config"
)

// ProcessFileURLsIfNeeded reads the response body, attempts to inject signed download URLs
// and signed upload URLs, and writes back the possibly modified body. It is safe to call;
// on any error it restores the original body and returns without propagating errors.
func ProcessFileURLsIfNeeded(ctx context.Context, cfg config.Config, resp *http.Response) {
	ct := resp.Header.Get("Content-Type")
	if ct == "" || !strings.Contains(ct, "application/json") {
		return
	}

	var buf bytes.Buffer
	if resp.Body != nil {
		if _, err := io.Copy(&buf, resp.Body); err != nil {
			return
		}
		_ = resp.Body.Close()
	}

	// Chain processors: first inject download URLs, then inject upload URLs
	processed := buf.Bytes()

	// Process download file URLs
	var err error
	processed, err = InjectSignedFileURLs(ctx, cfg, processed)
	if err != nil || processed == nil {
		processed = buf.Bytes()
	}

	// Process upload URLs
	processed, err = InjectSignedUploadURL(ctx, cfg, processed)
	if err != nil || processed == nil {
		processed = buf.Bytes()
	}

	resp.Body = io.NopCloser(bytes.NewReader(processed))
	resp.ContentLength = int64(len(processed))
	resp.Header.Set("Content-Length", strconv.Itoa(len(processed)))
}
