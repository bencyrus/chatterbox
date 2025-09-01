package main

import (
	"encoding/json"
	"log"
	"net/http"

	"github.com/bencyrus/chatterbox/files/internal/config"
)

const (
	placeholderImageURL = "https://images.unsplash.com/photo-1514888286974-6c03e2ca1dba"
)

func main() {
	cfg := config.Load()

	mux := http.NewServeMux()
	mux.HandleFunc("/signed_url", handleSignedURL())
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	srv := &http.Server{Addr: ":" + cfg.Port, Handler: mux}
	log.Printf("files service listening on :%s", cfg.Port)
	log.Fatal(srv.ListenAndServe())
}

func handleSignedURL() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		w.Header().Set("Content-Type", "application/json")

		var body map[string]any
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			http.Error(w, "invalid json", http.StatusBadRequest)
			return
		}

		arr, ok := body["files"]
		if !ok {
			http.Error(w, "missing files", http.StatusBadRequest)
			return
		}

		items, ok := arr.([]any)
		if !ok {
			http.Error(w, "files must be an array", http.StatusBadRequest)
			return
		}

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
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte("[]"))
			return
		}

		enc := json.NewEncoder(w)
		_ = enc.Encode(out)
	}
}
