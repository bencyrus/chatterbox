package main

import (
	"context"
	"log"
	"net/http"
	"time"

	"github.com/bencyrus/chatterbox/files/internal/config"
	"github.com/bencyrus/chatterbox/files/internal/database"
	"github.com/bencyrus/chatterbox/files/internal/gcs"
	"github.com/bencyrus/chatterbox/files/internal/httpserver"
	"github.com/bencyrus/chatterbox/files/internal/proxytoken"
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

	// GCS data client for server-side streaming (proxy upload/download).
	dataClient, err := gcs.NewDataClient(
		ctx,
		cfg.GCSSigningEmail,
		cfg.GCSSigningPrivateKey,
		cfg.StorageEmulatorHost,
	)
	if err != nil {
		logger.Error(ctx, "failed to initialize GCS data client", err)
		log.Fatal(err)
	}
	defer dataClient.Close()

	signer := proxytoken.NewSigner(cfg.ProxySigningSecret)

	httpSrv := httpserver.NewServer(cfg, db, dataClient, signer)

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", httpSrv.HealthzHandler)
	mux.HandleFunc("/signed_download_url", httpSrv.SignedDownloadURLHandler)
	mux.HandleFunc("/signed_upload_url", httpSrv.SignedUploadURLHandler)
	mux.HandleFunc("/signed_delete_url", httpSrv.SignedDeleteURLHandler)

	// Proxy URL minting (called by the gateway, behind the API key).
	mux.HandleFunc("/proxy_upload_url", httpSrv.ProxyUploadURLHandler)
	mux.HandleFunc("/proxy_download_url", httpSrv.ProxyDownloadURLHandler)

	// Streaming proxy endpoints (reached by end users, authorized by token).
	mux.HandleFunc("/u/", httpSrv.UploadProxyHandler)
	mux.HandleFunc("/d/", httpSrv.DownloadProxyHandler)

	// Enforce FILE_SERVICE_API_KEY on all endpoints except /healthz and the
	// token-authorized streaming endpoints (/u/, /d/).
	protected := httpSrv.WithAPIKeyAuth(mux)

	// Wrap with request ID middleware
	handler := middleware.RequestIDMiddleware(protected)

	// Note: ReadTimeout/WriteTimeout are intentionally left unset (0) so large
	// media uploads/downloads are not truncated mid-stream. ReadHeaderTimeout
	// guards against slow-header (slowloris) connections.
	srv := &http.Server{
		Addr:              ":" + cfg.Port,
		Handler:           handler,
		ReadHeaderTimeout: 10 * time.Second,
	}
	logger.Info(ctx, "files service server starting", logger.Fields{"address": srv.Addr})
	log.Fatal(srv.ListenAndServe())
}
