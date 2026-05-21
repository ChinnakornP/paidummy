// Package room owns room/match lifecycle: it is the authoritative bridge
// between connected players and the pure game engine. The engine never does
// I/O; this layer persists snapshots to Redis and results to Postgres.
package room

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math/rand"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/andaseacode/paidummy-server/internal/bot"
	"github.com/andaseacode/paidummy-server/internal/db"
	"github.com/andaseacode/paidummy-server/internal/game"
	"github.com/andaseacode/paidummy-server/internal/store"
	"github.com/google/uuid"
)

// Sender is the minimal interface a connected client exposes to a room: a way
// to push one serialized server message and an identity.
type Sender interface {
	GuestID() string
	Name() string
	Send(payload []byte)
}

// seat is one player's slot in a room.
type seat struct {
	GuestID string
	Name    string
	Avatar  string
	Ready   bool
	// BotMode short-circuits the per-turn shot clock for this seat so the
	// server auto-plays their turn within ~1.5s. Toggled either explicitly
	// via the "bot_takeover" WS message or implicitly after a disconnected
	// seat misses their first shot clock.
	BotMode bool
	client  Sender // nil when disconnected
}

// Room is a single table. All mutation goes through its mutex; the engine is
// pure so the critical section is short.
type Room struct {
	ID          string
	Name        string
	MaxPlayers  int
	TargetScore int
	Bet         int // coins each loser pays the winner at match end
	Host        string
	// Practice rooms run the full ruleset but do NOT settle coins at match
	// end and are not surfaced to QuickJoin (private to their creator).
	Practice bool
	// BotLevel tunes auto-played seats: "easy" (naive draw/dump), "normal"
	// (solver-driven melds + discards), "hard" (also knocks the moment a
	// going-out plan exists). Defaults to "normal".
	BotLevel string
	// Password gates Join when non-empty. Stored verbatim — never logged.
	Password string
	// TurnTimerSec overrides the default 60 s shot clock per turn. 0 means
	// use turnTimerDuration.
	TurnTimerSec int

	mu       sync.Mutex
	seats    []*seat
	rules    game.RuleSet
	engine   game.Engine
	state    *game.GameState
	matchID  uuid.UUID
	roundNo  int
	scores   map[string]int   // guestID -> cumulative match score
	coins    map[string]int64 // guestID -> last-known wallet balance
	finished bool

	// Auto-start countdown: when ≥MinPlayers are seated we arm a timer so the
	// round starts without requiring everyone to press "พร้อม". Filling to
	// MaxPlayers shortens it to 5s.
	countdownEnd   time.Time
	countdownTimer *time.Timer

	// Per-turn shot clock. Armed when a new turn opens (PhaseDraw begins for a
	// new active player) and cleared when the turn ends (discard advances or
	// round finishes). On expiry the server auto-plays draw_deck → discard
	// (the player's first card). It never auto-knocks.
	turnEnd   time.Time
	turnTimer *time.Timer

	// Spectators are view-only connections (not seated). They receive every
	// broadcast as a viewFor(-1) projection (empty hand, your_seat:-1) and
	// can't send game actions.
	spectators []Sender

	hub *Hub
}

// Room timing knobs — single source of truth for per-room durations so the
// values aren't sprinkled through the file.
const (
	// turnTimerDuration is the per-turn shot clock. On expiry the server
	// auto-plays draw_deck → discard (never knocks). Same value used both at
	// startRound and whenever a discard advances the turn.
	turnTimerDuration = 60 * time.Second
)

// turnTimerOverride returns the per-room shot-clock value, falling back to
// the package default when no custom value was set at creation time.
func (r *Room) turnTimerOverride() time.Duration {
	if r.TurnTimerSec > 0 {
		return time.Duration(r.TurnTimerSec) * time.Second
	}
	return turnTimerDuration
}

// Hub is the registry of live rooms plus the durable/ephemeral stores.
type Hub struct {
	mu    sync.RWMutex
	rooms map[string]*Room
	db    *db.DB
	store *store.Store
}

func NewHub(d *db.DB, s *store.Store) *Hub {
	return &Hub{rooms: map[string]*Room{}, db: d, store: s}
}

var (
	ErrRoomNotFound = errors.New("room not found")
	ErrRoomFull     = errors.New("room is full")
	ErrRoomStarted  = errors.New("room already started")
	ErrBadPassword  = errors.New("invalid room password")
)

// CreateOpts bundles the room-creation knobs surfaced through the custom-
// room sheet. Zero values fall back to the documented defaults so callers
// who only want a public bet-tier room (like QuickJoin) can leave the
// extras alone.
type CreateOpts struct {
	Name         string
	Password     string
	MaxPlayers   int
	TargetScore  int
	Bet          int
	TurnTimerSec int
	BotLevel     string // "easy" | "normal" | "hard"; empty → "normal"
	MinMeldLen   int    // variant rule: min cards per meld (3 default, 4 = harder)
}

// CreateRoom registers a new open room hosted by hostGuest.
func (h *Hub) CreateRoom(ctx context.Context, hostGuest, hostName, name string, max, target, bet int) *Room {
	return h.CreateRoomFull(ctx, hostGuest, hostName, CreateOpts{
		Name: name, MaxPlayers: max, TargetScore: target, Bet: bet,
	})
}

// CreateRoomFull is the extended room constructor used by custom-room
// creation. It populates password + per-turn timer overrides in addition
// to the basic fields.
func (h *Hub) CreateRoomFull(ctx context.Context, hostGuest, hostName string, opts CreateOpts) *Room {
	max := opts.MaxPlayers
	if max < 2 || max > 4 {
		max = 4
	}
	rs := game.DefaultRuleSet()
	if opts.TargetScore > 0 {
		rs.TargetScore = opts.TargetScore
	}
	// Variant rule: a custom room may require larger melds (3 → 4).
	if opts.MinMeldLen == 3 || opts.MinMeldLen == 4 {
		rs.MinMeldLen = opts.MinMeldLen
	}
	bet := opts.Bet
	if bet <= 0 {
		bet = 100 // default stake, like the classic "เดิมพัน 100"
	}
	level := opts.BotLevel
	switch level {
	case "easy", "normal", "hard":
	default:
		level = "normal"
	}
	r := &Room{
		ID: uuid.NewString(), Name: opts.Name, MaxPlayers: max,
		TargetScore: rs.TargetScore, Bet: bet, Host: hostGuest,
		Password:     opts.Password,
		TurnTimerSec: opts.TurnTimerSec,
		BotLevel:     level,
		rules:        rs, scores: map[string]int{},
		coins: map[string]int64{}, hub: h,
	}
	h.mu.Lock()
	h.rooms[r.ID] = r
	h.mu.Unlock()
	h.persistRoomMeta(ctx, r, true)
	return r
}

// QuickJoin is the server-managed matchmaking entrypoint. It seats the guest
// in the first open room matching the bet tier; if none exists, it creates
// a new one for that tier. The room is opaque to the player — they only
// chose a stake.
func (h *Hub) QuickJoin(ctx context.Context, guestID, guestName string, bet int) (*Room, error) {
	if bet <= 0 {
		bet = 100
	}
	// Look for the first open room at this stake.
	h.mu.RLock()
	var pick *Room
	for _, r := range h.rooms {
		r.mu.Lock()
		// Practice and password-protected rooms are private to their host
		// and never matched through QuickJoin.
		open := !r.Practice && r.Password == "" && r.state == nil && r.Bet == bet && len(r.seats) < r.MaxPlayers
		alreadySeated := false
		for _, s := range r.seats {
			if s.GuestID == guestID {
				alreadySeated = true
				break
			}
		}
		r.mu.Unlock()
		if open || alreadySeated {
			pick = r
			break
		}
	}
	h.mu.RUnlock()
	if pick == nil {
		pick = h.CreateRoom(ctx, guestID, guestName, fmt.Sprintf("เดิมพัน %d", bet), 4, 0, bet)
	}
	if err := pick.Join(guestID, guestName); err != nil {
		return nil, err
	}
	return pick, nil
}

// CreatePractice spins up a solo training room (host + 3 bots, no coin
// settlement). Returns the seated, ready-to-play room.
func (h *Hub) CreatePractice(ctx context.Context, guestID, guestName, difficulty string) (*Room, error) {
	r := h.CreateRoomFull(ctx, guestID, guestName, CreateOpts{
		Name: "ฝึกซ้อม", MaxPlayers: 4, BotLevel: difficulty,
	})
	r.mu.Lock()
	r.Practice = true
	r.Bet = 0
	r.mu.Unlock()
	if err := r.Join(guestID, guestName); err != nil {
		return nil, err
	}
	// Fill with 3 bots so the round can start immediately.
	for i := 0; i < 3; i++ {
		if err := r.AddBot(ctx); err != nil {
			break
		}
	}
	return r, nil
}

// Get returns a live room by id.
func (h *Hub) Get(id string) (*Room, bool) {
	h.mu.RLock()
	defer h.mu.RUnlock()
	r, ok := h.rooms[id]
	return r, ok
}

// OpenRooms lists rooms still accepting players.
func (h *Hub) OpenRooms() []*Room {
	h.mu.RLock()
	defer h.mu.RUnlock()
	var out []*Room
	for _, r := range h.rooms {
		r.mu.Lock()
		open := r.state == nil && len(r.seats) < r.MaxPlayers
		r.mu.Unlock()
		if open {
			out = append(out, r)
		}
	}
	return out
}

func (h *Hub) persistRoomMeta(ctx context.Context, r *Room, open bool) {
	meta, _ := json.Marshal(map[string]any{
		"id": r.ID, "name": r.Name, "max": r.MaxPlayers,
		"target": r.TargetScore, "bet": r.Bet,
	})
	_ = h.store.SaveRoom(ctx, r.ID, meta, open)
}

// broadcastReferralBonus pushes a one-shot "referral_bonus" envelope to
// any seat in this room whose guest id matches the referee or referrer.
// Recipients not currently attached to this room receive the coin credit
// via their next /me refresh — this just lights up a snackbar if they're
// here right now.
func (r *Room) broadcastReferralBonus(referee, referrer uuid.UUID) {
	payload := map[string]any{
		"coins_added": db.ReferralBonus,
		"referee":     referee.String(),
		"referrer":    referrer.String(),
	}
	r.sendTo(referee.String(), "referral_bonus",
		map[string]any{"role": "referee", "data": payload})
	r.sendTo(referrer.String(), "referral_bonus",
		map[string]any{"role": "referrer", "data": payload})
}

// ensureAvatar populates the seat's Avatar field from Postgres if it's
// still blank (just-joined seat, or pre-migration row). Best-effort.
func (r *Room) ensureAvatar(ctx context.Context, guestID string) {
	r.mu.Lock()
	idx := r.seatIndex(guestID)
	if idx < 0 || r.seats[idx].Avatar != "" {
		r.mu.Unlock()
		return
	}
	r.mu.Unlock()
	gid, err := uuid.Parse(guestID)
	if err != nil {
		return
	}
	a, err := r.hub.db.Avatar(ctx, gid)
	if err != nil || a == "" {
		a = db.DefaultAvatar
	}
	r.mu.Lock()
	idx = r.seatIndex(guestID)
	if idx >= 0 {
		r.seats[idx].Avatar = a
	}
	r.mu.Unlock()
}

// ensureCoins caches a seat's wallet balance from Postgres if not already
// known. Best-effort: a lookup failure just leaves the cache untouched.
func (r *Room) ensureCoins(ctx context.Context, guestID string) {
	r.mu.Lock()
	_, known := r.coins[guestID]
	r.mu.Unlock()
	if known {
		return
	}
	if id, err := uuid.Parse(guestID); err == nil {
		if bal, err := r.hub.db.Coins(ctx, id); err == nil {
			r.mu.Lock()
			r.coins[guestID] = bal
			r.mu.Unlock()
		}
	}
}

// Join seats a guest (or returns the existing seat). Idempotent per guest.
// Public rooms accept any password; password-protected rooms require the
// configured value.
func (r *Room) Join(guestID, name string) error {
	return r.JoinWith(guestID, name, "")
}

// JoinWith is the password-aware seating call. An already-seated guest is
// allowed back in regardless of password (server keeps their seat).
func (r *Room) JoinWith(guestID, name, password string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	for _, s := range r.seats {
		if s.GuestID == guestID {
			return nil
		}
	}
	if r.Password != "" && r.Password != password {
		return ErrBadPassword
	}
	if r.state != nil {
		return ErrRoomStarted
	}
	if len(r.seats) >= r.MaxPlayers {
		return ErrRoomFull
	}
	r.seats = append(r.seats, &seat{GuestID: guestID, Name: name})
	return nil
}

// AttachSpectator binds a view-only connection. Always succeeds (no seat
// limit) and immediately pushes the current public state.
func (r *Room) AttachSpectator(c Sender) {
	r.mu.Lock()
	// De-dup by guest id so a reconnecting spectator doesn't pile up.
	gid := c.GuestID()
	filtered := r.spectators[:0]
	for _, s := range r.spectators {
		if s.GuestID() != gid {
			filtered = append(filtered, s)
		}
	}
	r.spectators = append(filtered, c)
	view := r.viewFor(-1)
	r.mu.Unlock()
	c.Send(mustMsg("room_state", view))
}

// DetachSpectator removes a spectator connection by guest id.
func (r *Room) DetachSpectator(guestID string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	out := r.spectators[:0]
	for _, s := range r.spectators {
		if s.GuestID() != guestID {
			out = append(out, s)
		}
	}
	r.spectators = out
}

func (r *Room) seatIndex(guestID string) int {
	for i, s := range r.seats {
		if s.GuestID == guestID {
			return i
		}
	}
	return -1
}

// Attach binds a live connection to a guest's seat and sends initial state.
func (r *Room) Attach(c Sender) {
	r.mu.Lock()
	idx := r.seatIndex(c.GuestID())
	if idx == -1 {
		if r.state == nil && len(r.seats) < r.MaxPlayers {
			r.seats = append(r.seats, &seat{GuestID: c.GuestID(), Name: c.Name()})
			idx = len(r.seats) - 1
		} else {
			r.mu.Unlock()
			c.Send(mustMsg("error", map[string]string{"message": "cannot join room"}))
			return
		}
	}
	r.seats[idx].client = c
	// Reconnect cancels auto-elected bot takeover so the player resumes
	// control of their own turns.
	r.seats[idx].BotMode = false
	gid := c.GuestID()
	r.mu.Unlock()
	r.broadcastState()
	// Pull the wallet balance in the background, then refresh so the seat
	// shows coins before the round starts.
	go func() {
		r.ensureCoins(context.Background(), gid)
		r.ensureAvatar(context.Background(), gid)
		r.broadcastState()
	}()
	// Re-evaluate the auto-start countdown now that the seat has filled.
	r.evaluateCountdown(context.Background())
}

// armCountdown schedules an auto-start after d; if a timer is already pending
// it is replaced. broadcastState pushes the new deadline to clients.
func (r *Room) armCountdown(ctx context.Context, d time.Duration) {
	r.mu.Lock()
	if r.state != nil {
		r.mu.Unlock()
		return
	}
	if r.countdownTimer != nil {
		r.countdownTimer.Stop()
	}
	r.countdownEnd = time.Now().Add(d)
	r.countdownTimer = time.AfterFunc(d, func() { r.tryAutoStart(ctx) })
	r.mu.Unlock()
	r.broadcastState()
}

// cancelCountdown stops any pending auto-start.
func (r *Room) cancelCountdown() {
	r.mu.Lock()
	if r.countdownTimer != nil {
		r.countdownTimer.Stop()
		r.countdownTimer = nil
	}
	r.countdownEnd = time.Time{}
	r.mu.Unlock()
}

// tryAutoStart fires when the countdown elapses: start only if the round is
// still pending and we still have enough players.
func (r *Room) tryAutoStart(ctx context.Context) {
	r.mu.Lock()
	ok := r.state == nil && len(r.seats) >= r.rules.MinPlayers
	r.mu.Unlock()
	if ok {
		r.startRound(ctx)
	}
}

// botTurnInterval is the collapsed shot clock used for bot-mode seats so
// the round doesn't burn the full per-turn deadline on every auto-played
// move. Short enough to keep the table moving, long enough that humans
// can read what happened.
const botTurnInterval = 1500 * time.Millisecond

// armTurnTimer (re)starts the per-turn shot clock for the current active
// player. When it fires, autoPlay performs draw_deck then discards the
// first held card — never knocks, per the room rule. Bot-mode seats use a
// much shorter window so their turns fast-forward.
func (r *Room) armTurnTimer(ctx context.Context, d time.Duration) {
	r.mu.Lock()
	if r.state == nil || r.state.RoundOver {
		r.mu.Unlock()
		return
	}
	if r.turnTimer != nil {
		r.turnTimer.Stop()
	}
	turn := r.state.Turn
	if turn >= 0 && turn < len(r.seats) && r.seats[turn].BotMode {
		d = botTurnInterval
	}
	r.turnEnd = time.Now().Add(d)
	r.turnTimer = time.AfterFunc(d, func() { r.autoPlay(ctx) })
	r.mu.Unlock()
}

func (r *Room) cancelTurnTimer() {
	r.mu.Lock()
	if r.turnTimer != nil {
		r.turnTimer.Stop()
		r.turnTimer = nil
	}
	r.turnEnd = time.Time{}
	r.mu.Unlock()
}

// autoPlay submits a forced move for the active player when the shot clock
// expires. It funnels through HandleMessage so the same validation, snapshot,
// broadcast, and timer-rearm pipeline a human triggers also runs here.
func (r *Room) autoPlay(ctx context.Context) {
	r.mu.Lock()
	if r.state == nil || r.state.RoundOver {
		r.mu.Unlock()
		return
	}
	turn := r.state.Turn
	if turn < 0 || turn >= len(r.seats) {
		r.mu.Unlock()
		return
	}
	// Auto-elect bot takeover for disconnected seats so subsequent turns
	// don't keep burning the full shot clock. Reconnect clears this in
	// Attach.
	if r.seats[turn].client == nil && !r.seats[turn].BotMode {
		r.seats[turn].BotMode = true
	}
	guestID := r.seats[turn].GuestID
	phase := r.state.Phase
	var discardCard string
	if phase == game.PhaseMeld && len(r.state.Players[turn].Hand) > 0 {
		discardCard = r.state.Players[turn].Hand[0].String()
	}
	r.mu.Unlock()

	r.mu.Lock()
	level := r.BotLevel
	r.mu.Unlock()

	if phase == game.PhaseDraw {
		r.HandleMessage(ctx, guestID, "draw_deck", []byte("{}"))
		// After the draw the round could be over (deck exhaust); re-check.
		r.mu.Lock()
		if r.state == nil || r.state.RoundOver ||
			r.state.Turn != turn || r.state.Phase != game.PhaseMeld ||
			len(r.state.Players[turn].Hand) == 0 {
			r.mu.Unlock()
			return
		}
		discardCard = r.state.Players[turn].Hand[0].String()
		r.mu.Unlock()
	}

	// "normal"/"hard" bots play through the solver: lay down melds + layoffs,
	// knock when possible (hard), then discard the recommended card. "easy"
	// keeps the naive draw-and-dump behaviour.
	if level != "easy" {
		r.autoPlaySmart(ctx, guestID, turn, level)
		return
	}

	if discardCard == "" {
		return
	}
	raw, _ := json.Marshal(map[string]string{"card": discardCard})
	r.HandleMessage(ctx, guestID, "discard", raw)
}

// autoPlaySmart drives a bot through its meld phase using the same hint
// engine humans get: lay every available meld/layoff, knock if "hard" and a
// going-out plan exists, then discard the suggested card. Bounded so a
// pathological suggestion loop can't spin forever.
func (r *Room) autoPlaySmart(ctx context.Context, guestID string, turn int, level string) {
	for i := 0; i < 8; i++ {
		r.mu.Lock()
		if r.state == nil || r.state.RoundOver ||
			r.state.Turn != turn || r.state.Phase != game.PhaseMeld {
			r.mu.Unlock()
			return
		}
		canKnock := level == "hard" && game.CanAutoKnock(r.state, turn)
		sug := game.SuggestMove(r.state, turn)
		r.mu.Unlock()

		if canKnock {
			r.HandleMessage(ctx, guestID, "auto_knock", []byte("{}"))
			return
		}
		switch sug.Kind {
		case "meld":
			raw, _ := json.Marshal(map[string]any{"cards": sug.Cards})
			r.HandleMessage(ctx, guestID, "meld", raw)
		case "layoff":
			raw, _ := json.Marshal(map[string]any{
				"meld_id": sug.MeldID, "cards": sug.Cards,
			})
			r.HandleMessage(ctx, guestID, "layoff", raw)
		default: // discard (or unknown) ends the turn
			card := ""
			if len(sug.Cards) > 0 {
				card = sug.Cards[0]
			} else {
				r.mu.Lock()
				if r.state != nil && turn < len(r.state.Players) &&
					len(r.state.Players[turn].Hand) > 0 {
					card = r.state.Players[turn].Hand[0].String()
				}
				r.mu.Unlock()
			}
			if card == "" {
				return
			}
			raw, _ := json.Marshal(map[string]string{"card": card})
			r.HandleMessage(ctx, guestID, "discard", raw)
			return
		}
	}
}

// evaluateCountdown re-decides the auto-start timing for the current seat
// count: 45s while we wait for more players to join, collapsing to 5s the
// moment the table fills so a full room doesn't sit idle. Idempotent —
// calling repeatedly with the same conditions is a no-op.
func (r *Room) evaluateCountdown(ctx context.Context) {
	r.mu.Lock()
	if r.state != nil {
		r.mu.Unlock()
		return
	}
	n := len(r.seats)
	min := r.rules.MinPlayers
	max := r.MaxPlayers
	timerArmed := r.countdownTimer != nil
	remaining := time.Until(r.countdownEnd)
	r.mu.Unlock()

	switch {
	case n < min:
		r.cancelCountdown()
	case n >= max:
		// Full table: collapse to a 5s start if we were waiting longer.
		if !timerArmed || remaining > 5*time.Second {
			r.armCountdown(ctx, 5*time.Second)
		}
	default:
		// At/above MinPlayers but room still has space — give incoming
		// players 45s to join before starting. Only arm if no timer is
		// already running (so each new seat doesn't reset the clock).
		if !timerArmed {
			r.armCountdown(ctx, 45*time.Second)
		}
	}
}

// Detach marks a guest's connection gone (seat is kept for reconnection).
func (r *Room) Detach(guestID string) {
	r.mu.Lock()
	if i := r.seatIndex(guestID); i != -1 {
		r.seats[i].client = nil
	}
	r.mu.Unlock()
	r.broadcastState()
}

var botSeq atomic.Int64

// AddBot seats an automated player. It mints a real guest_users row so the
// match_players / round_scores foreign keys hold exactly as for a human, then
// attaches a bot.Bot — which the room treats like any other Sender. The bot
// auto-readies and plays its turns through the normal HandleMessage path.
func (r *Room) AddBot(ctx context.Context) error {
	r.mu.Lock()
	if r.state != nil {
		r.mu.Unlock()
		return ErrRoomStarted
	}
	if len(r.seats) >= r.MaxPlayers {
		r.mu.Unlock()
		return ErrRoomFull
	}
	r.mu.Unlock()

	g, err := r.hub.db.CreateGuest(ctx, fmt.Sprintf("🤖 Bot %d", botSeq.Add(1)))
	if err != nil {
		return err
	}
	id := g.ID.String()
	r.mu.Lock()
	r.coins[id] = g.Coins
	r.mu.Unlock()
	b := bot.New(id, g.DisplayName, func(typ string, data map[string]any) {
		raw, _ := json.Marshal(data)
		r.HandleMessage(context.Background(), id, typ, raw)
	})
	r.Attach(b) // seats the bot (state == nil) and sends it the first frame
	return nil
}

// HandleMessage processes one decoded client envelope from guestID.
func (r *Room) HandleMessage(ctx context.Context, guestID string, typ string, data json.RawMessage) {
	switch typ {
	case "ready":
		r.handleReady(ctx, guestID)
	case "leave":
		r.Detach(guestID)
	case "chat":
		r.handleChat(guestID, data)
	case "bot_takeover":
		r.handleBotTakeover(guestID, data)
	case "suggest":
		r.handleSuggest(guestID)
	case "report":
		r.handleReport(ctx, guestID, data)
	case "draw_deck", "draw_discard", "meld", "layoff", "knock", "auto_knock", "discard":
		r.handleGameAction(ctx, guestID, typ, data)
	default:
		r.sendTo(guestID, "error", map[string]string{"message": "unknown message type"})
	}
}

// chatMaxLen caps the length of a single chat message server-side. Drops
// the tail rather than rejecting the message so the user isn't punished
// for a long paste.
const chatMaxLen = 200

// handleReport files a report against the player at the given seat. The
// client reports by seat (it never sees opponent guest ids); the room
// resolves the target here and persists via db.CreateReport.
func (r *Room) handleReport(ctx context.Context, guestID string, data json.RawMessage) {
	var payload struct {
		Seat   int    `json:"seat"`
		Reason string `json:"reason"`
	}
	if err := json.Unmarshal(data, &payload); err != nil {
		return
	}
	r.mu.Lock()
	if payload.Seat < 0 || payload.Seat >= len(r.seats) {
		r.mu.Unlock()
		return
	}
	target := r.seats[payload.Seat].GuestID
	r.mu.Unlock()
	if target == guestID {
		return
	}
	reporter, e1 := uuid.Parse(guestID)
	tgt, e2 := uuid.Parse(target)
	if e1 != nil || e2 != nil {
		return
	}
	_ = r.hub.db.CreateReport(ctx, reporter, tgt, payload.Reason)
	r.sendTo(guestID, "report_ack", map[string]any{"seat": payload.Seat})
}

// handleSuggest computes a single recommended move for the requesting
// player (the "ช่วยคิด" hint) and replies privately. Read-only; available
// only on the player's own turn.
func (r *Room) handleSuggest(guestID string) {
	r.mu.Lock()
	if r.state == nil {
		r.mu.Unlock()
		return
	}
	idx := r.seatIndex(guestID)
	if idx < 0 || idx != r.state.Turn {
		r.mu.Unlock()
		return
	}
	sug := game.SuggestMove(r.state, idx)
	r.mu.Unlock()
	r.sendTo(guestID, "suggestion", map[string]any{
		"kind":    sug.Kind,
		"cards":   sug.Cards,
		"meld_id": sug.MeldID,
		"reason":  sug.Reason,
	})
}

// handleBotTakeover flips the per-seat BotMode flag, which short-circuits
// the shot clock so the server plays the turn quickly on the player's
// behalf. Idempotent — toggling to the current value is a no-op.
func (r *Room) handleBotTakeover(guestID string, data json.RawMessage) {
	var payload struct {
		Enabled bool `json:"enabled"`
	}
	if err := json.Unmarshal(data, &payload); err != nil {
		return
	}
	r.mu.Lock()
	idx := r.seatIndex(guestID)
	if idx < 0 || r.seats[idx].BotMode == payload.Enabled {
		r.mu.Unlock()
		return
	}
	r.seats[idx].BotMode = payload.Enabled
	r.mu.Unlock()
	r.broadcastState()
}

// handleChat broadcasts a chat line from the sender to every attached
// player. Ephemeral — no Postgres persistence. Empty/whitespace-only
// messages are silently dropped.
func (r *Room) handleChat(guestID string, data json.RawMessage) {
	var payload struct {
		Text string `json:"text"`
	}
	if err := json.Unmarshal(data, &payload); err != nil {
		return
	}
	text := strings.TrimSpace(payload.Text)
	if text == "" {
		return
	}
	if len(text) > chatMaxLen {
		text = text[:chatMaxLen]
	}
	r.mu.Lock()
	seat := r.seatIndex(guestID)
	if seat < 0 {
		r.mu.Unlock()
		return
	}
	name := r.seats[seat].Name
	r.mu.Unlock()
	r.broadcast("chat", map[string]any{
		"seat": seat,
		"name": name,
		"text": text,
		"ts":   time.Now().UnixMilli(),
	})
}

func (r *Room) handleReady(ctx context.Context, guestID string) {
	r.mu.Lock()
	// Rematch path — if the prior match has been settled, the first ready
	// after match_result is treated as a fresh-match request: cumulative
	// scores reset, roundNo zeroes so startRound mints a new matchID, and
	// the finished flag clears so the auto-start countdown re-arms.
	if r.finished {
		r.scores = map[string]int{}
		r.finished = false
		r.roundNo = 0
		for _, s := range r.seats {
			s.Ready = false
		}
	}
	if i := r.seatIndex(guestID); i != -1 {
		r.seats[i].Ready = true
	}
	allReady := len(r.seats) >= r.rules.MinPlayers
	for _, s := range r.seats {
		if !s.Ready {
			allReady = false
		}
	}
	start := allReady && r.state == nil
	r.mu.Unlock()
	if start {
		r.startRound(ctx)
	} else {
		r.broadcastState()
	}
}

func (r *Room) startRound(ctx context.Context) {
	r.mu.Lock()
	// Guard against double-start from converging triggers (countdown + ready).
	if r.state != nil {
		r.mu.Unlock()
		return
	}
	// Clear any pending countdown — the round is happening now.
	if r.countdownTimer != nil {
		r.countdownTimer.Stop()
		r.countdownTimer = nil
	}
	r.countdownEnd = time.Time{}
	ids := make([]string, len(r.seats))
	for i, s := range r.seats {
		ids[i] = s.GuestID
	}
	seed := time.Now().UnixNano() ^ rand.Int63()
	gs, _, err := r.engine.Start(ids, r.rules, seed)
	if err != nil {
		r.mu.Unlock()
		return
	}
	r.state = gs
	r.roundNo++
	firstRound := r.roundNo == 1
	if firstRound {
		r.matchID = uuid.New()
	}
	mid, ids2 := r.matchID, append([]string(nil), ids...)
	r.mu.Unlock()

	// Make sure every seat's wallet balance is cached for display + settlement.
	for _, id := range ids2 {
		r.ensureCoins(ctx, id)
	}

	if firstRound {
		players := make([]uuid.UUID, len(ids2))
		for i, s := range ids2 {
			players[i], _ = uuid.Parse(s)
		}
		rj, _ := json.Marshal(map[string]int{
			"target": r.TargetScore, "bet": r.Bet,
		})
		_ = r.hub.db.CreateMatch(ctx, mid, r.ID, r.TargetScore, r.Bet, rj, players)
		r.hub.persistRoomMeta(ctx, r, false)
	}
	r.snapshot(ctx)
	r.broadcastState()
	r.armTurnTimer(ctx, r.turnTimerOverride())
	r.broadcastTurn()
}

func (r *Room) handleGameAction(ctx context.Context, guestID, typ string, data json.RawMessage) {
	r.mu.Lock()
	if r.state == nil {
		r.mu.Unlock()
		r.sendTo(guestID, "error", map[string]string{"message": "round not started"})
		return
	}
	idx := r.seatIndex(guestID)
	act, err := decodeAction(typ, data)
	if err != nil {
		r.mu.Unlock()
		r.sendTo(guestID, "error", map[string]string{"message": err.Error()})
		return
	}
	beforePts := sumOwnedMeldPoints(r.state, idx)
	beforeDumps := snapshotDumpPenalties(r.state)
	_, err = r.engine.ApplyAction(r.state, idx, act)
	if err != nil {
		r.mu.Unlock()
		r.sendTo(guestID, "error", map[string]string{"message": err.Error()})
		return
	}
	deltaPts := sumOwnedMeldPoints(r.state, idx) - beforePts
	afterDumps := snapshotDumpPenalties(r.state)
	// Identify any per-seat dump-penalty increases so the affected seat can
	// see an immediate "-N แต้ม (ทิ้งเต็ม/ดัมมี่)" badge instead of waiting
	// for round-end scoring to surface it.
	penaltyDeltas := make([]int, len(afterDumps))
	for i := range afterDumps {
		if i < len(beforeDumps) {
			penaltyDeltas[i] = afterDumps[i] - beforeDumps[i]
		} else {
			penaltyDeltas[i] = afterDumps[i]
		}
	}
	seatGuests := make([]string, len(r.seats))
	for i, s := range r.seats {
		seatGuests[i] = s.GuestID
	}
	over := r.state.RoundOver
	phaseAfter := r.state.Phase
	r.mu.Unlock()

	if deltaPts > 0 {
		r.sendTo(guestID, "action_points", map[string]any{
			"points": deltaPts,
			"action": typ,
		})
	}
	for seat, delta := range penaltyDeltas {
		if delta <= 0 || seat >= len(seatGuests) {
			continue
		}
		// Reason: ทิ้งดัมมี่ if the penalty hit a seat *other* than the
		// actor (their card was picked up); ทิ้งเต็ม if the actor took
		// the hit themselves.
		reason := "dummy"
		if seat == idx {
			reason = "full"
		}
		r.sendTo(seatGuests[seat], "penalty_points", map[string]any{
			"points": delta,
			"reason": reason,
		})
	}
	r.snapshot(ctx)
	r.broadcastState()
	if over {
		r.cancelTurnTimer()
		r.finishRound(ctx)
		return
	}
	// Discard advances the turn → engine returns to PhaseDraw for the next
	// player. That's the one moment we restart the shot clock; during a
	// player's own draw→meld transitions the existing timer keeps running.
	if phaseAfter == game.PhaseDraw {
		r.armTurnTimer(ctx, r.turnTimerOverride())
	}
	r.broadcastTurn()
}

func (r *Room) finishRound(ctx context.Context) {
	// Defensive: the round is over, the shot clock must not still be ticking.
	r.cancelTurnTimer()
	r.mu.Lock()
	gs := r.state
	sb := game.ScoreRound(gs)
	scores := make([]db.RoundScore, 0, len(sb))
	var knocker *uuid.UUID
	if gs.Knocker >= 0 {
		if id, e := uuid.Parse(r.seats[gs.Knocker].GuestID); e == nil {
			knocker = &id
		}
	}
	for i, s := range sb {
		r.scores[r.seats[i].GuestID] += s.Total
		bj, _ := json.Marshal(s)
		gid, _ := uuid.Parse(r.seats[i].GuestID)
		scores = append(scores, db.RoundScore{GuestID: gid, Score: s.Total, Breakdown: bj})
	}
	mid := r.matchID
	roundNo := r.roundNo
	seed := gs.Seed
	reason := gs.EndReason
	var winnerGuest string
	best := -1 << 30
	reached := false
	for _, s := range r.seats {
		if r.scores[s.GuestID] >= r.TargetScore {
			reached = true
		}
		if r.scores[s.GuestID] > best {
			best = r.scores[s.GuestID]
			winnerGuest = s.GuestID
		}
	}
	totals := map[string]int{}
	for _, s := range r.seats {
		totals[s.GuestID] = r.scores[s.GuestID]
	}
	resultPayload := roundResult(r, sb)
	r.state = nil // ready for next round / rematch
	for _, s := range r.seats {
		s.Ready = false
	}
	if reached {
		r.finished = true
	}
	r.mu.Unlock()

	_ = r.hub.db.SaveRound(ctx, mid, roundNo, seed, reason, knocker, scores)
	r.broadcast("round_result", resultPayload)

	// Daily-mission: a knock this round counts toward the knocker's
	// "น็อค N ครั้ง" mission. Best-effort; never blocks the result flow.
	if reason == "knock" && knocker != nil {
		_ = r.hub.db.IncrementMissions(ctx, *knocker, db.MissionKnock, 1)
	}

	if reached {
		wg, _ := uuid.Parse(winnerGuest)
		_ = r.hub.db.FinishMatch(ctx, mid, wg)
		_ = r.hub.store.ClearGame(ctx, mid.String())

		// Daily-mission: every seated player completed a match ("เล่น N
		// ตา"); the winner also gets a "ชนะ N ตา" credit. Best-effort.
		r.mu.Lock()
		missionSeats := make([]string, 0, len(r.seats))
		for _, s := range r.seats {
			missionSeats = append(missionSeats, s.GuestID)
		}
		r.mu.Unlock()
		for _, gid := range missionSeats {
			id, e := uuid.Parse(gid)
			if e != nil {
				continue
			}
			_ = r.hub.db.IncrementMissions(ctx, id, db.MissionPlay, 1)
			if gid == winnerGuest {
				_ = r.hub.db.IncrementMissions(ctx, id, db.MissionWin, 1)
			}
		}

		// Coin settlement: every loser pays the bet to the winner.
		r.mu.Lock()
		var losers []uuid.UUID
		for _, s := range r.seats {
			if s.GuestID == winnerGuest {
				continue
			}
			if id, e := uuid.Parse(s.GuestID); e == nil {
				losers = append(losers, id)
			}
		}
		bet := int64(r.Bet)
		practice := r.Practice
		r.mu.Unlock()

		coinDeltas := map[string]int{}
		balances := map[string]int{}
		if !practice && bet > 0 && len(losers) > 0 {
			d, b, err := r.hub.db.SettleMatch(ctx, wg, bet, losers)
			if err == nil {
				r.mu.Lock()
				for id, nb := range b {
					r.coins[id.String()] = nb
					balances[id.String()] = int(nb)
				}
				for id, dv := range d {
					coinDeltas[id.String()] = int(dv)
				}
				r.mu.Unlock()

				// Persist per-player settlement rows — feeds /me/history,
				// /rooms/:id/history, and rank stats.
				settles := make([]db.SettlementRow, 0, len(d))
				for id, dv := range d {
					settles = append(settles, db.SettlementRow{
						GuestID:      id,
						CoinDelta:    int(dv),
						BalanceAfter: b[id],
						IsWinner:     id == wg,
					})
				}
				_ = r.hub.db.RecordSettlement(ctx, mid, settles)
				// Best-effort one-shot referral bonus for first-match wins
				// (winner + losers). Failures here never block the result
				// broadcast.
				for id := range d {
					awarded, ref, err := r.hub.db.MaybeAwardReferral(ctx, id)
					if err != nil || !awarded {
						continue
					}
					r.broadcastReferralBonus(id, ref)
				}
			}
		}
		r.mu.Lock()
		rows := make([]map[string]any, 0, len(r.seats))
		winnerName := ""
		for i, s := range r.seats {
			if s.GuestID == winnerGuest {
				winnerName = s.Name
			}
			rows = append(rows, map[string]any{
				"seat":       i,
				"name":       s.Name,
				"score":      totals[s.GuestID],
				"coin_delta": coinDeltas[s.GuestID],
				"balance":    balances[s.GuestID],
				"winner":     s.GuestID == winnerGuest,
			})
		}
		r.mu.Unlock()
		r.broadcast("match_result", map[string]any{
			"winner": winnerName,
			"bet":    r.Bet,
			"rows":   rows,
		})
		r.broadcastState()
	} else {
		r.broadcastState()
	}
}

func (r *Room) snapshot(ctx context.Context) {
	r.mu.Lock()
	if r.state == nil {
		r.mu.Unlock()
		return
	}
	b, _ := json.Marshal(r.state)
	mid := r.matchID.String()
	r.mu.Unlock()
	_ = r.hub.store.SaveGame(ctx, mid, b)
}

// --- broadcasting ---

func (r *Room) broadcast(typ string, data any) {
	r.mu.Lock()
	clients := make([]Sender, 0, len(r.seats)+len(r.spectators))
	for _, s := range r.seats {
		if s.client != nil {
			clients = append(clients, s.client)
		}
	}
	clients = append(clients, r.spectators...)
	r.mu.Unlock()
	msg := mustMsg(typ, data)
	for _, c := range clients {
		c.Send(msg)
	}
}

func (r *Room) broadcastState() {
	r.mu.Lock()
	defer r.mu.Unlock()
	for i, s := range r.seats {
		if s.client == nil {
			continue
		}
		s.client.Send(mustMsg("room_state", r.viewFor(i)))
	}
	// Spectators all share the same hand-less projection.
	if len(r.spectators) > 0 {
		specView := mustMsg("room_state", r.viewFor(-1))
		for _, s := range r.spectators {
			s.Send(specView)
		}
	}
}

func (r *Room) broadcastTurn() {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.state == nil {
		return
	}
	turn := r.state.Turn
	if turn < 0 || turn >= len(r.seats) {
		return
	}
	if c := r.seats[turn].client; c != nil {
		c.Send(mustMsg("your_turn", map[string]any{
			"phase":   r.state.Phase.String(),
			"allowed": allowedActions(r.state.Phase),
		}))
	}
}

func (r *Room) sendTo(guestID, typ string, data any) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if i := r.seatIndex(guestID); i != -1 && r.seats[i].client != nil {
		r.seats[i].client.Send(mustMsg(typ, data))
	}
}

// snapshotDumpPenalties copies the per-seat penalty totals so the action
// handler can diff them after applying a move.
func snapshotDumpPenalties(gs *game.GameState) []int {
	if gs == nil {
		return nil
	}
	out := make([]int, len(gs.DumpPenalties))
	copy(out, gs.DumpPenalties)
	return out
}

// sumOwnedMeldPoints totals the meld value of every meld owned by player p.
// We diff this before/after each action to surface the delta as a one-shot
// "action_points" message — that's the "เก็บไพ่ ได้แต้ม" notification the UI
// renders as a transient "+N แต้ม" badge.
func sumOwnedMeldPoints(gs *game.GameState, p int) int {
	if gs == nil {
		return 0
	}
	total := 0
	for _, m := range gs.Melds {
		if m.Owner == p {
			total += game.MeldPoints(m, gs.RuleSet)
		}
	}
	return total
}

func allowedActions(p game.Phase) []string {
	switch p {
	case game.PhaseDraw:
		return []string{"draw_deck", "draw_discard"}
	case game.PhaseMeld:
		return []string{"meld", "layoff", "knock", "auto_knock", "discard"}
	default:
		return nil
	}
}

func mustMsg(typ string, data any) []byte {
	raw, _ := json.Marshal(data)
	env, _ := json.Marshal(map[string]any{
		"type": typ, "ts": time.Now().Unix(), "data": json.RawMessage(raw),
	})
	return env
}

func decodeAction(typ string, data json.RawMessage) (game.Action, error) {
	switch typ {
	case "draw_deck":
		return game.Action{Type: game.ActDrawDeck}, nil
	case "draw_discard":
		var d struct {
			Card   string   `json:"card"` // optional: target card in the pile
			Cards  []string `json:"cards"`
			MeldID string   `json:"meld_id"` // ฝากดัมมี่: layoff target meld
		}
		_ = json.Unmarshal(data, &d)
		cs, err := parseCards(d.Cards)
		var target game.Card
		if d.Card != "" {
			tc, perr := game.ParseCard(d.Card)
			if perr != nil {
				return game.Action{}, perr
			}
			target = tc
		}
		return game.Action{
			Type:   game.ActDrawDiscard,
			Cards:  cs,
			Card:   target,
			MeldID: d.MeldID,
		}, err
	case "meld":
		var d struct {
			Cards []string `json:"cards"`
		}
		_ = json.Unmarshal(data, &d)
		cs, err := parseCards(d.Cards)
		return game.Action{Type: game.ActMeld, Cards: cs}, err
	case "layoff":
		var d struct {
			MeldID string   `json:"meld_id"`
			Cards  []string `json:"cards"`
		}
		_ = json.Unmarshal(data, &d)
		cs, err := parseCards(d.Cards)
		return game.Action{Type: game.ActLayOff, MeldID: d.MeldID, Cards: cs}, err
	case "knock":
		var d struct {
			Card string `json:"card"`
			Dark bool   `json:"dark"`
		}
		_ = json.Unmarshal(data, &d)
		c, err := game.ParseCard(d.Card)
		return game.Action{Type: game.ActKnock, Card: c, Dark: d.Dark}, err
	case "auto_knock":
		return game.Action{Type: game.ActAutoKnock}, nil
	case "discard":
		var d struct {
			Card string `json:"card"`
		}
		_ = json.Unmarshal(data, &d)
		c, err := game.ParseCard(d.Card)
		return game.Action{Type: game.ActDiscard, Card: c}, err
	}
	return game.Action{}, fmt.Errorf("unknown action %q", typ)
}

func parseCards(ss []string) ([]game.Card, error) {
	out := make([]game.Card, 0, len(ss))
	for _, s := range ss {
		c, err := game.ParseCard(s)
		if err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, nil
}
