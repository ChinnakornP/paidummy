package game

import "errors"

// LayOffEnd selects which end of a run a lay-off targets. Sets ignore it.
type LayOffEnd uint8

const (
	LayOffAuto LayOffEnd = iota
	LayOffHead
	LayOffTail
)

var errLayOffInvalid = errors.New("cards cannot be laid off onto that meld")

// canLayOff reports whether adding cards to meld m keeps it a valid meld of the
// same kind, and returns the resulting (re-sorted) meld. Any player may lay off
// onto any table meld (ฝาก). Correctness is enforced by reclassifying the
// combined cards: a run stays a same-suit consecutive sequence (Ace boundaries
// and the no-wrap rule fall out of classifyRun), a set stays one rank.
func canLayOff(m Meld, cards []Card, rs RuleSet) (Meld, error) {
	if len(cards) == 0 {
		return Meld{}, errLayOffInvalid
	}
	combined := make([]Card, 0, len(m.Cards)+len(cards))
	combined = append(combined, m.Cards...)
	combined = append(combined, cards...)

	kind, aceHigh, err := classifyMeld(combined, rs)
	if err != nil || kind != m.Kind {
		return Meld{}, errLayOffInvalid
	}
	out := Meld{ID: m.ID, Kind: kind, Cards: combined, Owner: m.Owner, AceHigh: aceHigh}
	if kind == MeldRun {
		sortRun(out.Cards, aceHigh)
	}
	return out, nil
}
