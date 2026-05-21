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
	"github.com/andaseacode/paidummy-server/internal/payment"
	"github.com/andaseacode/paidummy-server/internal/room"
	"github.com/andaseacode/paidummy-server/internal/session"
	"github.com/andaseacode/paidummy-server/internal/store"
	"github.com/andaseacode/paidummy-server/internal/ws"
	"github.com/google/uuid"
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

	// Anti-collusion: rescan the settlement graph every 30 min in the
	// background. Best-effort; failures just log.
	go func() {
		t := time.NewTicker(30 * time.Minute)
		defer t.Stop()
		for {
			if n, err := database.ScanCollusion(context.Background()); err != nil {
				log.Printf("collusion scan: %v", err)
			} else if n > 0 {
				log.Printf("collusion scan: flagged %d pair(s)", n)
			}
			<-t.C
		}
	}()

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
		Tiers:    room.TiersHandler(hub),
		Packages:    room.PackagesHandler(),
		Purchase:    room.PurchaseHandler(database, payment.MockProvider{}),
		MyHistory:   room.CoinHistoryHandler(database),
		RoomHistory: room.RoomHistoryHandler(database),
		Replay:      room.ReplayHandler(database),
		Tournaments: room.TournamentsHandler(),
		DailyStatus: room.DailyStatusHandler(database),
		DailyClaim:  room.DailyClaimHandler(database),
		DeviceToken: room.DeviceTokenHandler(database),
		Leaderboard:  room.LeaderboardHandler(database),
		Avatar:       room.AvatarHandler(database),
		Theme:        room.ThemeHandler(database),
		Missions:     room.MissionsHandler(database),
		MissionClaim: room.ClaimMissionHandler(database),

		Friends:        room.FriendsHandler(database),
		FriendRequests: room.FriendRequestsHandler(database),
		FriendRequest:  room.FriendRequestHandler(database),
		FriendAccept:   room.FriendAcceptHandler(database),

		AdStatus:     room.AdStatusHandler(database),
		AdClaim:      room.AdClaimHandler(database),
		Report:       room.ReportHandler(database),
		AdminBan:     room.AdminBanHandler(database),
		AdminReports: room.AdminReportsHandler(database),
		AdminToken:   cfg.AdminToken,
		IsBanned: func(id string) bool {
			gid, err := uuid.Parse(id)
			if err != nil {
				return false
			}
			return database.IsBanned(context.Background(), gid)
		},
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
