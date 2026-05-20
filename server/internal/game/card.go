// Package game is the pure, deterministic Thai Dummy (ไพ่ดัมมี่) rules engine.
// It imports only the Go standard library: no network, database, or framework
// dependencies. This keeps every rule unit-testable in isolation.
package game

import (
	"fmt"
	"strings"
)

// Suit of a playing card.
type Suit uint8

const (
	Clubs Suit = iota
	Diamonds
	Hearts
	Spades
)

// suitChars maps a Suit to its single-letter string form.
var suitChars = [...]byte{'C', 'D', 'H', 'S'}

func (s Suit) String() string { return string(suitChars[s]) }

// Rank of a playing card. Ace is 1; in a run it may also act high (above King).
type Rank uint8

const (
	Ace Rank = iota + 1
	Two
	Three
	Four
	Five
	Six
	Seven
	Eight
	Nine
	Ten
	Jack
	Queen
	King
)

// rankChars maps a Rank (1..13) to its display character.
var rankChars = [...]byte{0, 'A', '2', '3', '4', '5', '6', '7', '8', '9', 'T', 'J', 'Q', 'K'}

func (r Rank) String() string { return string(rankChars[r]) }

// Card is an immutable playing card value.
type Card struct {
	Suit Suit
	Rank Rank
}

// String renders a card as rank+suit, e.g. "2C", "QS", "TD", "AH".
func (c Card) String() string { return c.Rank.String() + c.Suit.String() }

// ParseCard parses the canonical "<rank><suit>" form (e.g. "QS", "TD", "AH").
// It is the inverse of Card.String and is used by the engine tests and the
// WebSocket protocol layer.
func ParseCard(s string) (Card, error) {
	s = strings.TrimSpace(strings.ToUpper(s))
	if len(s) != 2 {
		return Card{}, fmt.Errorf("invalid card %q: want 2 chars", s)
	}
	var r Rank
	for i, ch := range rankChars {
		if i != 0 && ch == s[0] {
			r = Rank(i)
			break
		}
	}
	if r == 0 {
		return Card{}, fmt.Errorf("invalid card %q: bad rank %c", s, s[0])
	}
	var su Suit = 255
	for i, ch := range suitChars {
		if ch == s[1] {
			su = Suit(i)
			break
		}
	}
	if su == 255 {
		return Card{}, fmt.Errorf("invalid card %q: bad suit %c", s, s[1])
	}
	return Card{Suit: su, Rank: r}, nil
}

// MustCard is ParseCard that panics on error; for tests and static data only.
func MustCard(s string) Card {
	c, err := ParseCard(s)
	if err != nil {
		panic(err)
	}
	return c
}

// IsSpeto reports whether the card is a Speto (เสปโต) card under the ruleset
// (by default 2♣ and Q♠), each worth SpetoPoints.
func (c Card) IsSpeto(rs RuleSet) bool {
	for _, s := range rs.SpetoCards {
		if s == c {
			return true
		}
	}
	return false
}

// Points returns the scoring value of the card under the given ruleset.
// aceHigh selects the Ace value when it terminates the high end of a run
// (e.g. Q-K-A); elsewhere the Ace scores low.
func (c Card) Points(rs RuleSet, aceHigh bool) int {
	if c.IsSpeto(rs) {
		return rs.SpetoPoints
	}
	switch {
	case c.Rank == Ace:
		if aceHigh {
			return rs.AceHighPoints
		}
		return rs.AceLowPoints
	case c.Rank >= Ten: // T, J, Q, K
		return rs.FaceCardPoints
	default: // 2..9
		return int(c.Rank)
	}
}
