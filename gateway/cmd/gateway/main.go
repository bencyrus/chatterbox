package main

import (
	"log"
	"net/http"

	"github.com/bencyrus/chatterbox/gateway/internal/config"
	"github.com/bencyrus/chatterbox/gateway/internal/proxy"
)

func main() {
	cfg := config.Load()
	log.Printf("Starting gateway on :%s", cfg.Port)

	gw, err := proxy.NewGateway(cfg)
	if err != nil {
		log.Fatalf("failed to init gateway: %v", err)
	}

	srv := &http.Server{
		Addr:    ":" + cfg.Port,
		Handler: gw,
	}
	if err := srv.ListenAndServe(); err != nil {
		log.Fatalf("server error: %v", err)
	}
}
