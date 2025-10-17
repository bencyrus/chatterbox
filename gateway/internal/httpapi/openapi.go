package httpapi

import (
	"io"
	"net/http"
	"time"

	"github.com/bencyrus/chatterbox/gateway/internal/config"
	"github.com/bencyrus/chatterbox/shared/logger"
)

// NewOpenAPIHandler returns an http.Handler that proxies to PostgREST and returns
// the OpenAPI schema in JSON. It forwards Authorization so the schema reflects
// the caller's role.
func NewOpenAPIHandler(cfg config.Config) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx := r.Context()

		client := &http.Client{Timeout: time.Duration(cfg.HTTPClientTimeoutSeconds) * time.Second}

		url := cfg.PostgRESTURL
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
		if err != nil {
			logger.Error(ctx, "failed to build openapi request", err)
			http.Error(w, "failed to fetch openapi", http.StatusBadGateway)
			return
		}

		if authz := r.Header.Get("Authorization"); authz != "" {
			req.Header.Set("Authorization", authz)
		}
		req.Header.Set("Accept", "application/openapi+json")

		resp, err := client.Do(req)
		if err != nil {
			logger.Error(ctx, "openapi request failed", err)
			http.Error(w, "failed to fetch openapi", http.StatusBadGateway)
			return
		}
		defer resp.Body.Close()

		for k, vals := range resp.Header {
			for _, v := range vals {
				w.Header().Add(k, v)
			}
		}
		if w.Header().Get("Content-Type") == "" {
			w.Header().Set("Content-Type", "application/openapi+json")
		}
		w.WriteHeader(resp.StatusCode)
		if _, err := io.Copy(w, resp.Body); err != nil {
			logger.Error(ctx, "failed to write openapi response", err)
		}
	})
}

