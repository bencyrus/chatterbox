package main

import (
	"encoding/json"
	"log"
	"net/http"
	"strconv"

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
		fileIDs := toInt64Slice(arr)
		if len(fileIDs) == 0 {
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte("[]"))
			return
		}

		// Build [{"file_id": <number>, "url": "<url>"}, ...]
		out := make([]map[string]any, 0, len(fileIDs))
		for _, fileID := range fileIDs {
			out = append(out, map[string]any{
				"file_id": fileID,
				"url":     placeholderImageURL,
			})
		}

		enc := json.NewEncoder(w)
		_ = enc.Encode(out)
	}
}

func toInt64Slice(v any) []int64 {
	res := make([]int64, 0)
	switch vv := v.(type) {
	case []any:
		for _, item := range vv {
			switch t := item.(type) {
			case float64:
				id := int64(t)
				if float64(id) == t {
					res = append(res, id)
				}
			case string:
				if t == "" {
					continue
				}
				if n, err := strconv.ParseInt(t, 10, 64); err == nil {
					res = append(res, n)
				}
			default:
				// ignore unsupported types
			}
		}
	}
	return res
}
