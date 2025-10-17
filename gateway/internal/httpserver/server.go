package httpserver

import (
	"net/http"

	"github.com/bencyrus/chatterbox/gateway/internal/config"
	"github.com/bencyrus/chatterbox/gateway/internal/httpapi"
	"github.com/bencyrus/chatterbox/gateway/internal/proxy"
	"github.com/bencyrus/chatterbox/shared/middleware"
)

// NewHandler builds the top-level HTTP handler for the gateway.
// It wires all HTTP endpoints and mounts the reverse proxy as the catch-all.
func NewHandler(cfg config.Config) (http.Handler, error) {
	gw, err := proxy.NewGateway(cfg)
	if err != nil {
		return nil, err
	}

	mux := http.NewServeMux()
	// Gateway endpoints
	mux.Handle("/openapi.json", httpapi.NewOpenAPIHandler(cfg))

	// Catch-all: reverse proxy to PostgREST
	mux.Handle("/", gw)

	// Wrap with shared middleware
	return middleware.RequestIDMiddleware(mux), nil
}
