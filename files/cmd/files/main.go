package main

import (
	"context"
	"log"
	"net/http"

	"github.com/bencyrus/chatterbox/files/internal/config"
	"github.com/bencyrus/chatterbox/files/internal/database"
	"github.com/bencyrus/chatterbox/files/internal/httpserver"
	"github.com/bencyrus/chatterbox/shared/logger"
	"github.com/bencyrus/chatterbox/shared/middleware"
)

func main() {
	cfg := config.Load()

	// Initialize the centralized logger
	logger.Init("files")
	ctx := context.Background()

	logger.Info(ctx, "starting files http server", logger.Fields{"port": cfg.Port})

	db, err := database.NewClient(cfg.DatabaseURL)
	if err != nil {
		logger.Error(ctx, "failed to initialize database", err)
		log.Fatal(err)
	}

	httpSrv := httpserver.NewServer(cfg, db)

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", httpSrv.HealthzHandler)
	mux.HandleFunc("/signed_url", httpSrv.SignedURLHandler)

	// Enforce FILE_SERVICE_API_KEY on all endpoints except /healthz.
	protected := httpSrv.WithAPIKeyAuth(mux)

	// Wrap with request ID middleware
	handler := middleware.RequestIDMiddleware(protected)

	srv := &http.Server{Addr: ":" + cfg.Port, Handler: handler}
	logger.Info(ctx, "files service server starting", logger.Fields{"address": srv.Addr})
	log.Fatal(srv.ListenAndServe())
}
