// Package bot is a server-side auto-player. A Bot satisfies room.Sender
// structurally (GuestID/Name/Send), so the room treats it like any connected
// client: it receives room_state frames and, on its turn, submits moves back
// through the same path a human would. Move legality is delegated to the real
// engine (game.NewMeld), so a bot can never make an illegal play.
package bot

import (
	"encoding/json"
	"math/rand"
	"sort"
	"sync"
	"time"

	"github.com/andaseacode/paidummy-server/internal/game"
)

// Submit delivers one action into the owning room (async; never called while
// the room lock is held).
type Submit func(typ string, data map[string]any)

// Bot plays a single seat automatically with a light heuristic.
type Bot struct {
	id   string
	name string
	send Submit
	rs   game.RuleSet

	mu      sync.Mutex
	readied bool
	pending bool
	started bool
	phase   string
	turn    int
	seat    int
	hand    []string
}

// New builds a bot. submit must enqueue work without blocking on room locks.
func New(id, name string, submit Submit) *Bot {
	return &Bot{id: id, name: name, send: submit, rs: game.DefaultRuleSet()}
}

func (b *Bot) GuestID() string { return b.id }
func (b *Bot) Name() string    { return b.name }

// Send is invoked by the room (under its lock) for every server frame. It only
// records state and schedules a deferred decision; it must not call back
// synchronously.
func (b *Bot) Send(payload []byte) {
	var env struct {
		Type string          `json:"type"`
		Data json.RawMessage `json:"data"`
	}
	if json.Unmarshal(payload, &env) != nil {
		return
	}
	if env.Type != "room_state" {
		return // your_turn/player_action/etc. — room_state carries all we need
	}
	var st struct {
		Started  bool     `json:"started"`
		Phase    string   `json:"phase"`
		Turn     int      `json:"turn"`
		YourSeat int      `json:"your_seat"`
		YourHand []string `json:"your_hand"`
	}
	if json.Unmarshal(env.Data, &st) != nil {
		return
	}

	b.mu.Lock()
	b.started, b.phase = st.Started, st.Phase
	b.turn, b.seat, b.hand = st.Turn, st.YourSeat, st.YourHand
	needReady := !st.Started && !b.readied
	myMove := st.Started && st.Turn == st.YourSeat &&
		(st.Phase == "draw" || st.Phase == "meld")
	schedule := !b.pending && (needReady || myMove)
	if schedule {
		b.pending = true
	}
	b.mu.Unlock()

	if !schedule {
		return
	}
	// "Think" briefly, then act. Variance keeps multi-bot tables from moving
	// in lockstep and reads naturally to a human opponent.
	delay := time.Duration(250+rand.Intn(350)) * time.Millisecond
	time.AfterFunc(delay, b.act)
}

func (b *Bot) act() {
	b.mu.Lock()
	b.pending = false
	started, phase, turn, seat := b.started, b.phase, b.turn, b.seat
	hand := append([]string(nil), b.hand...)
	if !started && !b.readied {
		b.readied = true
		b.mu.Unlock()
		b.send("ready", map[string]any{})
		return
	}
	b.mu.Unlock()

	if !started || turn != seat {
		return
	}
	switch phase {
	case "draw":
		b.send("draw_deck", map[string]any{})
	case "meld":
		if len(hand) == 0 {
			return // nothing to do; wait for the next authoritative frame
		}
		if len(hand) == 1 {
			b.send("knock", map[string]any{"card": hand[0]})
			return
		}
		if meld := b.bestMeld(hand); meld != nil {
			b.send("meld", map[string]any{"cards": meld})
			return
		}
		b.send("discard", map[string]any{"card": b.discardChoice(hand)})
	}
}

// bestMeld returns the largest subset of hand that the engine accepts as a
// valid set/run, or nil. Validity is decided by game.NewMeld, never reimplemented.
func (b *Bot) bestMeld(hand []string) []string {
	cards := make([]game.Card, 0, len(hand))
	for _, s := range hand {
		c, err := game.ParseCard(s)
		if err != nil {
			return nil
		}
		cards = append(cards, c)
	}
	// Always keep at least one card to discard (or to knock with at len 1),
	// so a meld may never empty the hand.
	maxSize := len(cards) - 1
	if maxSize > 5 {
		maxSize = 5 // bound the search; 3..5 covers all sets and useful runs
	}
	for size := maxSize; size >= 3; size-- {
		var found []string
		combos(len(cards), size, func(idx []int) bool {
			pick := make([]game.Card, len(idx))
			for i, k := range idx {
				pick[i] = cards[k]
			}
			if _, err := game.NewMeld("probe", pick, 0, b.rs); err == nil {
				found = make([]string, len(idx))
				for i, k := range idx {
					found[i] = hand[k]
				}
				return true // stop
			}
			return false
		})
		if found != nil {
			return found
		}
	}
	return nil
}

// discardChoice drops the least-connected card (fewest same-rank or adjacent
// same-suit partners), breaking ties by highest point value.
func (b *Bot) discardChoice(hand []string) string {
	cards := make([]game.Card, len(hand))
	for i, s := range hand {
		c, _ := game.ParseCard(s)
		cards[i] = c
	}
	type scored struct {
		card      string
		connected int
		points    int
	}
	ranked := make([]scored, len(hand))
	for i, c := range cards {
		conn := 0
		for j, o := range cards {
			if i == j {
				continue
			}
			if o.Rank == c.Rank {
				conn += 2
			}
			if o.Suit == c.Suit {
				d := int(o.Rank) - int(c.Rank)
				if d == 1 || d == -1 || d == 2 || d == -2 {
					conn++
				}
			}
		}
		ranked[i] = scored{hand[i], conn, c.Points(b.rs, false)}
	}
	sort.Slice(ranked, func(i, j int) bool {
		if ranked[i].connected != ranked[j].connected {
			return ranked[i].connected < ranked[j].connected
		}
		return ranked[i].points > ranked[j].points
	})
	return ranked[0].card
}

// combos invokes fn with each k-combination of [0,n); fn returning true stops.
func combos(n, k int, fn func([]int) bool) {
	idx := make([]int, k)
	var rec func(start, depth int) bool
	rec = func(start, depth int) bool {
		if depth == k {
			return fn(idx)
		}
		for i := start; i <= n-(k-depth); i++ {
			idx[depth] = i
			if rec(i+1, depth+1) {
				return true
			}
		}
		return false
	}
	if k >= 0 && k <= n {
		rec(0, 0)
	}
}
