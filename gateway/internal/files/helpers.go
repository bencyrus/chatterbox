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

// ProcessFileURLsIfNeeded reads the response body, attempts to inject signed URLs,
// and writes back the possibly modified body. It is safe to call; on any error it restores
// the original body and returns without propagating errors.
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

	processed, err := InjectSignedFileURLs(ctx, cfg, buf.Bytes())
	if err != nil || processed == nil {
		resp.Body = io.NopCloser(bytes.NewReader(buf.Bytes()))
		resp.ContentLength = int64(buf.Len())
		resp.Header.Set("Content-Length", strconv.Itoa(buf.Len()))
		return
	}

	resp.Body = io.NopCloser(bytes.NewReader(processed))
	resp.ContentLength = int64(len(processed))
	resp.Header.Set("Content-Length", strconv.Itoa(len(processed)))
}
