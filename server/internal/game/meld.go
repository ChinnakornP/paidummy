package game

import (
	"errors"
	"sort"
)

// MeldKind distinguishes a set (same rank) from a run (sequence in one suit).
type MeldKind uint8

const (
	MeldSet MeldKind = iota
	MeldRun
)

func (k MeldKind) String() string {
	if k == MeldRun {
		return "run"
	}
	return "set"
}

// Meld is a group of cards exposed on the table. Cards in a run are stored in
// ascending order; AceHigh records whether the Ace (if any) terminates the
// high end (Q-K-A) and therefore scores high.
type Meld struct {
	ID      string
	Kind    MeldKind
	Cards   []Card
	Owner   int  // player index that laid the meld (for scoring/head bonus)
	AceHigh bool // run only: Ace acts high
}

var (
	errMeldTooShort = errors.New("meld must have at least the minimum length")
	errMeldInvalid  = errors.New("cards do not form a valid set or run")
)

// classifyRun reports whether same-suit cards form a consecutive sequence, and
// if so whether the Ace (if present) is acting high. Duplicate ranks are
// rejected. No wrap: K-A-2 fails both Ace-low and Ace-high checks.
func classifyRun(cards []Card) (ok bool, aceHigh bool) {
	vals := make([]int, len(cards))
	hasAce := false
	for i, c := range cards {
		vals[i] = int(c.Rank)
		if c.Rank == Ace {
			hasAce = true
		}
	}
	consec := func(v []int) bool {
		s := append([]int(nil), v...)
		sort.Ints(s)
		for i := 1; i < len(s); i++ {
			if s[i] == s[i-1] || s[i] != s[i-1]+1 {
				return false
			}
		}
		return true
	}
	if consec(vals) {
		return true, false // Ace low (or no Ace)
	}
	if hasAce {
		hi := make([]int, len(vals))
		for i, v := range vals {
			if v == int(Ace) {
				v = int(King) + 1 // 14
			}
			hi[i] = v
		}
		if consec(hi) {
			return true, true
		}
	}
	return false, false
}

// classifyMeld validates a group and returns its kind. Sets are 3+ cards of one
// rank; runs are 3+ consecutive cards of one suit (Ace high or low, no wrap).
func classifyMeld(cards []Card, rs RuleSet) (MeldKind, bool, error) {
	if len(cards) < rs.MinMeldLen {
		return 0, false, errMeldTooShort
	}
	isSet := true
	for _, c := range cards {
		if c.Rank != cards[0].Rank {
			isSet = false
			break
		}
	}
	if isSet {
		return MeldSet, false, nil
	}
	for _, c := range cards {
		if c.Suit != cards[0].Suit {
			return 0, false, errMeldInvalid
		}
	}
	if ok, aceHigh := classifyRun(cards); ok {
		return MeldRun, aceHigh, nil
	}
	return 0, false, errMeldInvalid
}

// NewMeld validates cards and builds a Meld owned by owner. Run cards are
// returned sorted ascending (Ace ordered per the high/low it forms).
func NewMeld(id string, cards []Card, owner int, rs RuleSet) (Meld, error) {
	kind, aceHigh, err := classifyMeld(cards, rs)
	if err != nil {
		return Meld{}, err
	}
	out := append([]Card(nil), cards...)
	if kind == MeldRun {
		sortRun(out, aceHigh)
	}
	return Meld{ID: id, Kind: kind, Cards: out, Owner: owner, AceHigh: aceHigh}, nil
}

// sortRun orders run cards ascending; with aceHigh the Ace sorts above King.
func sortRun(cards []Card, aceHigh bool) {
	val := func(c Card) int {
		if aceHigh && c.Rank == Ace {
			return int(King) + 1
		}
		return int(c.Rank)
	}
	sort.Slice(cards, func(i, j int) bool { return val(cards[i]) < val(cards[j]) })
}
