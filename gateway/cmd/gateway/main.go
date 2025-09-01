package main

import (
	"context"
	"log"
	"net/http"

	"github.com/bencyrus/chatterbox/gateway/internal/config"
	"github.com/bencyrus/chatterbox/gateway/internal/proxy"
	"github.com/bencyrus/chatterbox/shared/logger"
	"github.com/bencyrus/chatterbox/shared/middleware"
)

func main() {
	cfg := config.Load()

	// Initialize the centralized logger
	logger.Init("gateway")
	ctx := context.Background()

	logger.Info(ctx, "starting gateway", logger.Fields{"port": cfg.Port})

	gw, err := proxy.NewGateway(cfg)
	if err != nil {
		logger.Error(ctx, "failed to init gateway", err)
		log.Fatalf("failed to init gateway: %v", err)
	}

	// Wrap the gateway with request ID middleware
	handler := middleware.RequestIDMiddleware(gw)

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
