package game

// Phase is the turn sub-state of the active player.
type Phase uint8

const (
	PhaseWaiting   Phase = iota // before the round is dealt
	PhaseDraw                   // active player must draw (deck or discard)
	PhaseMeld                   // drew; may meld / lay off / knock, then must discard
	PhaseRoundOver              // round finished; scores available
)

func (p Phase) String() string {
	switch p {
	case PhaseDraw:
		return "draw"
	case PhaseMeld:
		return "meld"
	case PhaseRoundOver:
		return "round_over"
	default:
		return "waiting"
	}
}

// Player holds a single seat's private hand and the melds they own.
type Player struct {
	ID    string
	Hand  []Card
	Melds []string // ids of table melds this player created (for head/scoring)
	// Produced is true once the player has laid at least one meld this round;
	// it gates whether a knock counts as "dark" (knocking before producing).
	Produced bool
	// ProducedAtTurnStart snapshots Produced at the moment this player's turn
	// began; a dark knock requires no production before the knocking turn.
	ProducedAtTurnStart bool
}

// GameState is the full authoritative state of one round. It is a plain value
// (slices it owns only) so it can be deep-copied, JSON serialized for Redis,
// and rehydrated deterministically from Seed.
type GameState struct {
	Players     []Player
	Turn        int    // index of the active player
	Phase       Phase  //
	DrawPile    []Card // face-down, draw from index 0
	DiscardPile []Card // face-up, top is last element
	Melds       []Meld // all melds exposed on the table
	HeadCard    Card   // เกิดหัว face-up card
	HeadOwner   int    // player who absorbed the head card into a meld, else -1
	Seed        int64  // shuffle seed (reproducibility / rehydration)
	FirstMove   bool   // true until the very first draw of the round (must be deck)
	RoundOver   bool
	EndReason   string // "knock" | "deck_exhaust"
	Knocker     int    // player who knocked, else -1
	KnockDark   bool   // knock was blind (no prior production)
	KnockSuit   bool   // knock formed an all-one-suit board for the knocker
	RuleSet     RuleSet
	NextMeldSeq int // monotonic counter backing meld ids
}

// activePlayer returns a pointer to the player whose turn it is.
func (gs *GameState) activePlayer() *Player { return &gs.Players[gs.Turn] }

// topDiscard returns the top discard card and whether the pile is non-empty.
func (gs *GameState) topDiscard() (Card, bool) {
	if len(gs.DiscardPile) == 0 {
		return Card{}, false
	}
	return gs.DiscardPile[len(gs.DiscardPile)-1], true
}

// findMeld returns the index of the table meld with the given id, or -1.
func (gs *GameState) findMeld(id string) int {
	for i := range gs.Melds {
		if gs.Melds[i].ID == id {
			return i
		}
	}
	return -1
}

// handContains reports whether player p's hand holds all of cards (counting
// multiplicity), without mutating anything.
func (gs *GameState) handContains(p int, cards []Card) bool {
	hand := gs.Players[p].Hand
	used := make([]bool, len(hand))
	for _, c := range cards {
		ok := false
		for i, h := range hand {
			if !used[i] && h == c {
				used[i] = true
				ok = true
				break
			}
		}
		if !ok {
			return false
		}
	}
	return true
}

// removeFromHand removes the given cards from player p's hand. It returns false
// and mutates nothing if any card is absent — callers validate before commit.
func (gs *GameState) removeFromHand(p int, cards []Card) bool {
	if !gs.handContains(p, cards) {
		return false
	}
	hand := gs.Players[p].Hand
	used := make([]bool, len(hand))
	for _, c := range cards {
		for i, h := range hand {
			if !used[i] && h == c {
				used[i] = true
				break
			}
		}
	}
	nh := make([]Card, 0, len(hand))
	for i, h := range hand {
		if !used[i] {
			nh = append(nh, h)
		}
	}
	gs.Players[p].Hand = nh
	return true
}
