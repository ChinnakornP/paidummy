//go:build integration

// Package integration drives a full two-player round over real WebSocket
// connections against real Postgres and Redis, and asserts both round
// persistence and the hand-privacy invariant (no client frame ever carries
// another player's cards). Requires `make up` first.
package integration

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/andaseacode/paidummy-server/internal/config"
	"github.com/andaseacode/paidummy-server/internal/db"
	"github.com/andaseacode/paidummy-server/internal/httpapi"
	"github.com/andaseacode/paidummy-server/internal/room"
	"github.com/andaseacode/paidummy-server/internal/session"
	"github.com/andaseacode/paidummy-server/internal/store"
	"github.com/andaseacode/paidummy-server/internal/ws"
	"github.com/google/uuid"
	"github.com/gorilla/websocket"
)

func mustJSONPost(t *testing.T, url, token, body string) map[string]any {
	t.Helper()
	req, _ := http.NewRequest(http.MethodPost, url, strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("POST %s: %v", url, err)
	}
	defer resp.Body.Close()
	var out map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		t.Fatalf("decode %s: %v", url, err)
	}
	if resp.StatusCode >= 300 {
		t.Fatalf("POST %s -> %d %v", url, resp.StatusCode, out)
	}
	return out
}

func TestFullRoundOverWebSocket(t *testing.T) {
	cfg := config.Load()
	ctx := context.Background()

	database, err := db.Connect(ctx, cfg.PGDSN)
	if err != nil {
		t.Skipf("postgres unavailable (run `make up`): %v", err)
	}
	defer database.Close()
	if err := database.Migrate(ctx); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	rds, err := store.Connect(ctx, cfg.RedisAddr)
	if err != nil {
		t.Skipf("redis unavailable (run `make up`): %v", err)
	}
	defer rds.Close()

	sessions := session.NewManager(database, rds, time.Hour)
	hub := room.NewHub(database, rds)
	srv := &httpapi.Server{
		Sessions: sessions,
		Rooms:    room.NewRESTAdapter(hub, database),
		History:  room.HistoryHandler(database),
		WS:       ws.NewHandler(hub, sessions),
	}

	ts := httptest.NewServer(srv.Router())
	defer ts.Close()
	wsBase := "ws" + strings.TrimPrefix(ts.URL, "http")

	alice := mustJSONPost(t, ts.URL+"/api/v1/guest", "", `{"display_name":"Alice"}`)
	bob := mustJSONPost(t, ts.URL+"/api/v1/guest", "", `{"display_name":"Bob"}`)
	aTok, bTok := alice["token"].(string), bob["token"].(string)

	created := mustJSONPost(t, ts.URL+"/api/v1/rooms", aTok, `{"name":"t","max_players":2}`)
	roomID := created["id"].(string)
	mustJSONPost(t, ts.URL+"/api/v1/rooms/"+roomID+"/join", bTok, `{}`)

	dial := func(tok string) *websocket.Conn {
		c, _, err := websocket.DefaultDialer.Dial(wsBase+"/ws?token="+tok+"&room="+roomID, nil)
		if err != nil {
			t.Fatalf("dial: %v", err)
		}
		return c
	}
	ca, cb := dial(aTok), dial(bTok)
	defer ca.Close()
	defer cb.Close()

	send := func(c *websocket.Conn, typ string, data any) {
		raw, _ := json.Marshal(data)
		_ = c.WriteJSON(map[string]any{"type": typ, "data": json.RawMessage(raw)})
	}

	// A bot reads frames and, on its turn, draws from the deck then discards
	// the first held card. Repeated deck draws exhaust the pile (29 cards) and
	// deterministically end the round with reason "deck_exhaust".
	roundResult := make(chan map[string]any, 2)
	leak := make(chan string, 8)
	runBot := func(c *websocket.Conn) {
		for {
			_, raw, err := c.ReadMessage()
			if err != nil {
				return
			}
			var env struct {
				Type string          `json:"type"`
				Data json.RawMessage `json:"data"`
			}
			if json.Unmarshal(raw, &env) != nil {
				continue
			}
			switch env.Type {
			case "room_state":
				var st struct {
					Phase    string           `json:"phase"`
					Turn     int              `json:"turn"`
					YourSeat int              `json:"your_seat"`
					YourHand []string         `json:"your_hand"`
					Players  []map[string]any `json:"players"`
				}
				_ = json.Unmarshal(env.Data, &st)
				for _, p := range st.Players {
					if _, bad := p["hand"]; bad {
						leak <- "players[].hand present"
					}
					if _, bad := p["cards"]; bad {
						leak <- "players[].cards present"
					}
				}
				if st.Turn != st.YourSeat {
					continue
				}
				switch st.Phase {
				case "draw":
					send(c, "draw_deck", map[string]any{})
				case "meld":
					if len(st.YourHand) > 0 {
						send(c, "discard", map[string]string{"card": st.YourHand[0]})
					}
				}
			case "round_result":
				var d map[string]any
				_ = json.Unmarshal(env.Data, &d)
				roundResult <- d
				return
			}
		}
	}
	go runBot(ca)
	go runBot(cb)

	send(ca, "ready", map[string]any{})
	send(cb, "ready", map[string]any{})

	select {
	case <-leak:
		t.Fatal("hand-privacy violated: a client frame exposed another player's cards")
	case rr := <-roundResult:
		if rr["reason"] != "deck_exhaust" {
			t.Fatalf("round ended with reason %v, want deck_exhaust", rr["reason"])
		}
		if _, ok := rr["scores"].([]any); !ok {
			t.Fatalf("round_result missing scores: %v", rr)
		}
	case <-time.After(15 * time.Second):
		t.Fatal("round did not complete in time")
	}

	var n int
	if err := database.Pool.QueryRow(ctx,
		`SELECT count(*) FROM rounds r JOIN matches m ON m.id=r.match_id WHERE m.room_id=$1`,
		roomID).Scan(&n); err != nil {
		t.Fatalf("count rounds: %v", err)
	}
	if n < 1 {
		t.Fatalf("expected >=1 persisted round, got %d", n)
	}
}

// TestCoinSettlement verifies the wallet math: a loser pays the bet (clamped
// to balance), the winner collects the pot, atomically.
func TestCoinSettlement(t *testing.T) {
	cfg := config.Load()
	ctx := context.Background()
	database, err := db.Connect(ctx, cfg.PGDSN)
	if err != nil {
		t.Skipf("postgres unavailable: %v", err)
	}
	defer database.Close()
	if err := database.Migrate(ctx); err != nil {
		t.Fatalf("migrate: %v", err)
	}

	win, err := database.CreateGuest(ctx, "Winner")
	if err != nil {
		t.Fatal(err)
	}
	lose, err := database.CreateGuest(ctx, "Loser")
	if err != nil {
		t.Fatal(err)
	}
	if win.Coins != db.StartingCoins || lose.Coins != db.StartingCoins {
		t.Fatalf("new guests should start at %d", db.StartingCoins)
	}

	deltas, balances, err := database.SettleMatch(ctx, win.ID, 150,
		[]uuid.UUID{lose.ID})
	if err != nil {
		t.Fatalf("settle: %v", err)
	}
	if deltas[lose.ID] != -150 || deltas[win.ID] != 150 {
		t.Fatalf("deltas wrong: %v", deltas)
	}
	if balances[lose.ID] != db.StartingCoins-150 ||
		balances[win.ID] != db.StartingCoins+150 {
		t.Fatalf("balances wrong: %v", balances)
	}

	// Over-bet: loser can never pay more than they hold.
	d2, b2, err := database.SettleMatch(ctx, win.ID, 1_000_000,
		[]uuid.UUID{lose.ID})
	if err != nil {
		t.Fatalf("settle2: %v", err)
	}
	if b2[lose.ID] != 0 {
		t.Fatalf("loser balance should clamp to 0, got %d", b2[lose.ID])
	}
	if d2[lose.ID] != -(db.StartingCoins - 150) {
		t.Fatalf("loser delta should be its whole remaining balance, got %d",
			d2[lose.ID])
	}
	got, _ := database.Coins(ctx, win.ID)
	if got != db.StartingCoins+150+(db.StartingCoins-150) {
		t.Fatalf("winner final balance wrong: %d", got)
	}
}

// TestBotPlaysRound: one human + one server bot complete and persist a round.
func TestBotPlaysRound(t *testing.T) {
	cfg := config.Load()
	ctx := context.Background()

	database, err := db.Connect(ctx, cfg.PGDSN)
	if err != nil {
		t.Skipf("postgres unavailable: %v", err)
	}
	defer database.Close()
	if err := database.Migrate(ctx); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	rds, err := store.Connect(ctx, cfg.RedisAddr)
	if err != nil {
		t.Skipf("redis unavailable: %v", err)
	}
	defer rds.Close()

	sessions := session.NewManager(database, rds, time.Hour)
	hub := room.NewHub(database, rds)
	srv := &httpapi.Server{
		Sessions: sessions,
		Rooms:    room.NewRESTAdapter(hub, database),
		History:  room.HistoryHandler(database),
		WS:       ws.NewHandler(hub, sessions),
	}
	ts := httptest.NewServer(srv.Router())
	defer ts.Close()
	wsBase := "ws" + strings.TrimPrefix(ts.URL, "http")

	human := mustJSONPost(t, ts.URL+"/api/v1/guest", "", `{"display_name":"Human"}`)
	tok := human["token"].(string)
	created := mustJSONPost(t, ts.URL+"/api/v1/rooms", tok, `{"name":"b","max_players":2}`)
	roomID := created["id"].(string)
	// Seat one server bot opposite the human.
	mustJSONPost(t, ts.URL+"/api/v1/rooms/"+roomID+"/bots", tok, `{"count":1}`)

	c, _, err := websocket.DefaultDialer.Dial(
		wsBase+"/ws?token="+tok+"&room="+roomID, nil)
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer c.Close()
	send := func(typ string, data any) {
		raw, _ := json.Marshal(data)
		_ = c.WriteJSON(map[string]any{"type": typ, "data": json.RawMessage(raw)})
	}

	done := make(chan map[string]any, 1)
	go func() {
		for {
			_, raw, err := c.ReadMessage()
			if err != nil {
				return
			}
			var env struct {
				Type string          `json:"type"`
				Data json.RawMessage `json:"data"`
			}
			if json.Unmarshal(raw, &env) != nil {
				continue
			}
			switch env.Type {
			case "room_state":
				var st struct {
					Phase    string   `json:"phase"`
					Turn     int      `json:"turn"`
					YourSeat int      `json:"your_seat"`
					YourHand []string `json:"your_hand"`
				}
				_ = json.Unmarshal(env.Data, &st)
				if st.Turn != st.YourSeat {
					continue
				}
				switch st.Phase {
				case "draw":
					send("draw_deck", map[string]any{})
				case "meld":
					if len(st.YourHand) > 0 {
						send("discard",
							map[string]string{"card": st.YourHand[0]})
					}
				}
			case "round_result":
				var d map[string]any
				_ = json.Unmarshal(env.Data, &d)
				done <- d
				return
			}
		}
	}()

	send("ready", map[string]any{}) // human ready; the bot auto-readies

	select {
	case rr := <-done:
		if _, ok := rr["scores"].([]any); !ok {
			t.Fatalf("round_result missing scores: %v", rr)
		}
	case <-time.After(70 * time.Second):
		t.Fatal("bot game did not complete (bot may not be playing)")
	}

	var n int
	if err := database.Pool.QueryRow(ctx,
		`SELECT count(*) FROM rounds r JOIN matches m ON m.id=r.match_id WHERE m.room_id=$1`,
		roomID).Scan(&n); err != nil {
		t.Fatalf("count rounds: %v", err)
	}
	if n < 1 {
		t.Fatalf("expected a persisted round with a bot, got %d", n)
	}
}
