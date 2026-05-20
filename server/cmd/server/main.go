// Command server is the Thai Dummy game server entrypoint. It wires config,
// Postgres, Redis, sessions, the room hub, and the HTTP+WebSocket surface.
package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/andaseacode/paidummy-server/internal/config"
	"github.com/andaseacode/paidummy-server/internal/db"
	"github.com/andaseacode/paidummy-server/internal/httpapi"
	"github.com/andaseacode/paidummy-server/internal/room"
	"github.com/andaseacode/paidummy-server/internal/session"
	"github.com/andaseacode/paidummy-server/internal/store"
	"github.com/andaseacode/paidummy-server/internal/ws"
)

func main() {
	cfg := config.Load()
	ctx := context.Background()

	database, err := db.Connect(ctx, cfg.PGDSN)
	if err != nil {
		log.Fatalf("postgres: %v", err)
	}
	defer database.Close()
	if err := database.Migrate(ctx); err != nil {
		log.Fatalf("migrate: %v", err)
	}

	rds, err := store.Connect(ctx, cfg.RedisAddr)
	if err != nil {
		log.Fatalf("redis: %v", err)
	}
	defer rds.Close()

	sessions := session.NewManager(database, rds, cfg.SessionTTL)
	hub := room.NewHub(database, rds)
	wsHandler := ws.NewHandler(hub, sessions)

	srv := &httpapi.Server{
		Sessions: sessions,
		WS:       wsHandler,
		Rooms:    room.NewRESTAdapter(hub, database),
		History:  room.HistoryHandler(database),
		Me:       room.MeHandler(database),
		Tiers:    room.TiersHandler(),
	}

	httpServer := &http.Server{
		Addr:              cfg.HTTPAddr,
		Handler:           srv.Router(),
		ReadHeaderTimeout: 10 * time.Second,
	}

	go func() {
		log.Printf("listening on %s", cfg.HTTPAddr)
		if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("http: %v", err)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop
	log.Println("shutting down")
	shutCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = httpServer.Shutdown(shutCtx)
}
