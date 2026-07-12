package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/panagiod/infra/apps/kubeship/internal/api"
	"github.com/panagiod/infra/apps/kubeship/internal/store"
	"github.com/panagiod/infra/apps/kubeship/static"
)

func main() {
	port := getenv("PORT", "8080")

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	st, err := store.OpenDefault(ctx)
	if err != nil {
		log.Fatalf("store: %v", err)
	}

	srv := &http.Server{
		Addr:              ":" + port,
		Handler:           api.New(st, static.Files).Handler(),
		ReadHeaderTimeout: 5 * time.Second,
	}

	go func() {
		log.Printf("kubeship listening on :%s", port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("listen: %v", err)
		}
	}()

	<-ctx.Done()
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = srv.Shutdown(shutdownCtx)
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
