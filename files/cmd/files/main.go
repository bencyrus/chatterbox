package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"

	"github.com/bencyrus/chatterbox/files/internal/config"
	"github.com/bencyrus/chatterbox/shared/logger"
	"github.com/bencyrus/chatterbox/shared/middleware"
)

const (
	placeholderImageURL = "https://images.unsplash.com/photo-1514888286974-6c03e2ca1dba"
)

func main() {
	cfg := config.Load()

	// Initialize the centralized logger
	logger.Init("files")
	ctx := context.Background()

	logger.Info(ctx, "starting files service", logger.Fields{"port": cfg.Port})

	mux := http.NewServeMux()
	mux.HandleFunc("/signed_url", handleSignedURL())
	mux.HandleFunc("/healthz", handleHealthz())

	// Wrap with request ID middleware
	handler := middleware.RequestIDMiddleware(mux)

	srv := &http.Server{Addr: ":" + cfg.Port, Handler: handler}
	logger.Info(ctx, "files service server starting", logger.Fields{"address": srv.Addr})
	log.Fatal(srv.ListenAndServe())
}

func handleHealthz() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ctx := r.Context()
		logger.Debug(ctx, "health check requested")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	}
}

func handleSignedURL() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ctx := r.Context()

		if r.Method != http.MethodPost {
			logger.Warn(ctx, "invalid method for signed_url endpoint", logger.Fields{
				"method": r.Method,
			})
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		w.Header().Set("Content-Type", "application/json")

		var body map[string]any
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			logger.Error(ctx, "failed to decode request body", err)
			http.Error(w, "invalid json", http.StatusBadRequest)
			return
		}

		arr, ok := body["files"]
		if !ok {
			logger.Warn(ctx, "missing files field in request")
			http.Error(w, "missing files", http.StatusBadRequest)
			return
		}

		items, ok := arr.([]any)
		if !ok {
			logger.Warn(ctx, "files field is not an array")
			http.Error(w, "files must be an array", http.StatusBadRequest)
			return
		}

		logger.Debug(ctx, "processing signed URL request", logger.Fields{
			"files_count": len(items),
		})

		out := make([]map[string]any, 0, len(items))
		for _, item := range items {
			switch v := item.(type) {
			case string:
				if v == "" {
					continue
				}
				out = append(out, map[string]any{
					"file_id": v,
					"url":     placeholderImageURL,
				})
			case float64:
				out = append(out, map[string]any{
					"file_id": v,
					"url":     placeholderImageURL,
				})
			default:
				// ignore unsupported types
			}
		}

		if len(out) == 0 {
			logger.Debug(ctx, "no valid files to process")
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte("[]"))
			return
		}

		logger.Info(ctx, "signed URLs generated successfully", logger.Fields{
			"processed_files": len(out),
		})

		enc := json.NewEncoder(w)
		if err := enc.Encode(out); err != nil {
			logger.Error(ctx, "failed to encode response", err)
			http.Error(w, "internal server error", http.StatusInternalServerError)
		}
	}
}
