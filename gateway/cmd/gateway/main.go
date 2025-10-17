package main

import (
	"context"
	"log"
	"net/http"

	"github.com/bencyrus/chatterbox/gateway/internal/config"
	"github.com/bencyrus/chatterbox/gateway/internal/httpserver"
	"github.com/bencyrus/chatterbox/shared/logger"
)

func main() {
	cfg := config.Load()

	// Initialize the centralized logger
	logger.Init("gateway")
	ctx := context.Background()

	logger.Info(ctx, "starting gateway", logger.Fields{"port": cfg.Port})

	handler, err := httpserver.NewHandler(cfg)
	if err != nil {
		logger.Error(ctx, "failed to init http server", err)
		log.Fatalf("failed to init http server: %v", err)
	}

	srv := &http.Server{
		Addr:    ":" + cfg.Port,
		Handler: handler,
	}

	logger.Info(ctx, "gateway server starting", logger.Fields{"address": srv.Addr})
	if err := srv.ListenAndServe(); err != nil {
		logger.Error(ctx, "server error", err)
		log.Fatalf("server error: %v", err)
	}
}
