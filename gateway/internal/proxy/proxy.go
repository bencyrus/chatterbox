package proxy

import (
	"net/http"
	"net/http/httputil"
	"net/url"
	"time"

	"github.com/bencyrus/chatterbox/gateway/internal/auth"
	"github.com/bencyrus/chatterbox/gateway/internal/config"
	fileops "github.com/bencyrus/chatterbox/gateway/internal/files"
	"github.com/bencyrus/chatterbox/shared/logger"
)

type Gateway struct {
	cfg       config.Config
	backend   *url.URL
	transport *http.Transport
}

func NewGateway(cfg config.Config) (*Gateway, error) {
	backend, err := url.Parse(cfg.PostgRESTURL)
	if err != nil {
		return nil, err
	}
	return &Gateway{
		cfg:     cfg,
		backend: backend,
		transport: &http.Transport{
			Proxy:              http.ProxyFromEnvironment,
			MaxIdleConns:       100,
			IdleConnTimeout:    90 * time.Second,
			DisableCompression: false,
		},
	}, nil
}

func (g *Gateway) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	logger.Debug(ctx, "processing request in gateway", logger.Fields{
		"backend_url": g.backend.String(),
		"method":      r.Method,
		"path":        r.URL.Path,
	})

	// Preflight token refresh only when the access token is nearing expiry
	var refreshed *auth.RefreshResult
	if auth.ShouldRefreshAccessToken(g.cfg, r.Header, time.Now()) && r.Header.Get(g.cfg.RefreshTokenHeaderIn) != "" {
		logger.Debug(ctx, "attempting token refresh")
		refreshed = auth.PreflightRefresh(ctx, g.cfg, r.Header, 2*time.Second)
		if refreshed != nil {
			logger.Info(ctx, "token refresh successful")
		}
	}

	proxy := &httputil.ReverseProxy{
		Director: func(req *http.Request) {
			// Forward to PostgREST backend
			req.URL.Scheme = g.backend.Scheme
			req.URL.Host = g.backend.Host
			// Preserve original path and query
			// Ensure X-Request-ID is present and forwarded
			if req.Header.Get("X-Request-ID") == "" {
				if rid, ok := req.Context().Value(logger.RequestIDKey).(string); ok && rid != "" {
					req.Header.Set("X-Request-ID", rid)
				}
			}
		},
		Transport: g.transport,
		ModifyResponse: func(resp *http.Response) error {
			// Attach any refreshed tokens if available
			auth.AttachRefreshedTokens(resp.Header, g.cfg, refreshed)

			// Process file URLs if needed
			fileops.ProcessFileURLsIfNeeded(ctx, g.cfg, resp)
			return nil
		},
	}

	proxy.ServeHTTP(w, r)
}
