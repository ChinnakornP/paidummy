package game

// RuleSet is the single source of truth for every tunable Thai Dummy constant.
// The published manual (dummy.gameindy.com) is ambiguous on several scoring and
// penalty details; rather than scatter magic numbers through the engine, every
// such value lives here behind a named field with a // TODO(spec) marker where
// the rule is uncertain. Engine logic never hard-codes a score.
type RuleSet struct {
	MinPlayers int
	MaxPlayers int
	// HandSize returns how many cards each player is dealt for a given player
	// count; the remainder forms the draw pile (minus one head card).
	HandSize func(numPlayers int) int

	MinMeldLen int // minimum cards in a valid run or set (3)

	// Card point values.
	SpetoPoints    int    // value of a Speto card (2♣, Q♠): 50
	FaceCardPoints int    // T, J, Q, K (non-Speto): 10
	AceLowPoints   int    // Ace scored low: 1
	AceHighPoints  int    // Ace terminating the high end of a run: 10 // TODO(spec): confirm
	SpetoCards     []Card // cards treated as Speto

	// Bonuses added to the relevant player's round score.
	KnockBonus     int // base knock (น็อค): 50
	KnockCardBonus int // the knock card itself: 50
	HeadCardBonus  int // เกิดหัว: head card ends up in a meld you own: 50

	// Knock multipliers applied to KnockBonus.
	// dark+suit stacks both => x4. // TODO(spec): confirm stacking vs flat x4.
	DarkKnockMult     int // blind/หลับ knock (no prior meld): 2
	SameSuitKnockMult int // monochrome knock (น็อคสี): 2

	// Penalties (subtracted).
	DumpPenalty int // -50 category for illegal/penalised discards // TODO(spec): clarify triggers
	// HandCardPenalty is the negative value of a card left in hand at round end.
	HandCardPenalty func(c Card, rs RuleSet) int

	TargetScore int // match ends when a player reaches this cumulative score
}

// DefaultRuleSet returns the documented Thai Dummy ruleset. Values flagged
// // TODO(spec) are best-effort from standard Thai Dummy play pending an
// authoritative source; change them here only.
func DefaultRuleSet() RuleSet {
	rs := RuleSet{
		MinPlayers:        2,
		MaxPlayers:        4,
		MinMeldLen:        3,
		SpetoPoints:       50,
		FaceCardPoints:    10,
		AceLowPoints:      1,
		AceHighPoints:     10,
		SpetoCards:        []Card{{Suit: Clubs, Rank: Two}, {Suit: Spades, Rank: Queen}},
		KnockBonus:        50,
		KnockCardBonus:    50,
		HeadCardBonus:     50,
		DarkKnockMult:     2,
		SameSuitKnockMult: 2,
		DumpPenalty:       50,
		TargetScore:       500, // TODO(spec): room-configurable (100/200/500 "P" rooms)
	}
	// HandSize: 2p->11, 3p->9, 4p->7 (standard Thai Dummy). // TODO(spec): verify per player count.
	rs.HandSize = func(n int) int {
		switch n {
		case 2:
			return 11
		case 3:
			return 9
		default:
			return 7
		}
	}
	// Cards left in hand are subtracted at face scoring value (Ace low).
	rs.HandCardPenalty = func(c Card, r RuleSet) int { return c.Points(r, false) }
	return rs
}
