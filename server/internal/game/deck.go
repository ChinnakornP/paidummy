package game

import "math/rand"

// NewDeck returns a fresh ordered 52-card deck (no jokers).
func NewDeck() []Card {
	d := make([]Card, 0, 52)
	for s := Clubs; s <= Spades; s++ {
		for r := Ace; r <= King; r++ {
			d = append(d, Card{Suit: s, Rank: r})
		}
	}
	return d
}

// Shuffle returns a new deterministically shuffled copy of cards using the
// given seed (Fisher-Yates). The same seed always yields the same order, which
// makes rounds reproducible for tests and for Redis state rehydration.
func Shuffle(cards []Card, seed int64) []Card {
	out := make([]Card, len(cards))
	copy(out, cards)
	rng := rand.New(rand.NewSource(seed))
	for i := len(out) - 1; i > 0; i-- {
		j := rng.Intn(i + 1)
		out[i], out[j] = out[j], out[i]
	}
	return out
}

// Deal distributes a shuffled deck for numPlayers. Each player gets
// rs.HandSize(numPlayers) cards, one card becomes the face-up head card, and
// the rest is the draw pile. Returns (hands, headCard, drawPile).
func Deal(deck []Card, numPlayers int, rs RuleSet) (hands [][]Card, head Card, draw []Card) {
	h := rs.HandSize(numPlayers)
	hands = make([][]Card, numPlayers)
	idx := 0
	for p := 0; p < numPlayers; p++ {
		hands[p] = make([]Card, h)
		copy(hands[p], deck[idx:idx+h])
		idx += h
	}
	head = deck[idx]
	idx++
	draw = append([]Card(nil), deck[idx:]...)
	return hands, head, draw
}
