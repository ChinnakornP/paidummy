package game

// Auto-knock solver: given a player's hand and the table's existing melds,
// find a way to lay down every card except one (the knock card) — either as
// new melds (≥ MinMeldLen, valid set or run) or as layoffs that extend the
// table melds — so the player can immediately go out.
//
// Strategy is depth-first backtracking: pin the lowest-index unplaced card,
// then try every group it could belong to (new meld or layoff onto each
// existing meld). Hand sizes in Thai Dummy stay ≤ 12 cards, so the search
// space stays small even with naive pruning.

// LayoffStep records a single planned layoff onto a table meld.
type LayoffStep struct {
	MeldID string
	Cards  []Card
}

// AutoKnockPlan is the partition the solver returns on success.
type AutoKnockPlan struct {
	NewMelds  [][]Card
	Layoffs   []LayoffStep
	KnockCard Card
}

// SolveAutoKnock searches for a knock-going-out plan from player p's current
// hand against the table's melds. Returns the plan and true if one exists.
// Pure: never mutates gs.
func SolveAutoKnock(gs *GameState, p int) (AutoKnockPlan, bool) {
	hand := append([]Card(nil), gs.Players[p].Hand...)
	rs := gs.RuleSet
	if len(hand) < 2 {
		return AutoKnockPlan{}, false
	}
	melds := append([]Meld(nil), gs.Melds...)

	for ki := 0; ki < len(hand); ki++ {
		rest := make([]Card, 0, len(hand)-1)
		rest = append(rest, hand[:ki]...)
		rest = append(rest, hand[ki+1:]...)
		newMelds, layoffs, ok := partitionForKnock(rest, melds, p, rs)
		if ok {
			return AutoKnockPlan{
				NewMelds:  newMelds,
				Layoffs:   layoffs,
				KnockCard: hand[ki],
			}, true
		}
	}
	return AutoKnockPlan{}, false
}

// partitionForKnock recursively splits `cards` into new melds and layoffs.
// Returns true on the first successful partition. The lowest-index card is
// always pinned into the next group to avoid duplicate permutations.
func partitionForKnock(cards []Card, melds []Meld, owner int, rs RuleSet) ([][]Card, []LayoffStep, bool) {
	if len(cards) == 0 {
		return nil, nil, true
	}
	pin := cards[0]
	others := cards[1:]
	n := len(others)

	for mask := 0; mask < (1 << n); mask++ {
		group := make([]Card, 0, n+1)
		group = append(group, pin)
		for i := 0; i < n; i++ {
			if mask&(1<<i) != 0 {
				group = append(group, others[i])
			}
		}
		if len(group) < rs.MinMeldLen {
			continue
		}
		if _, err := NewMeld("__try", group, owner, rs); err != nil {
			continue
		}
		rest := remainingByMask(others, mask)
		nm, lo, ok := partitionForKnock(rest, melds, owner, rs)
		if ok {
			return append([][]Card{group}, nm...), lo, true
		}
	}

	for mi, m := range melds {
		for mask := 0; mask < (1 << n); mask++ {
			group := make([]Card, 0, n+1)
			group = append(group, pin)
			for i := 0; i < n; i++ {
				if mask&(1<<i) != 0 {
					group = append(group, others[i])
				}
			}
			updated, err := canLayOff(m, group, rs)
			if err != nil {
				continue
			}
			rest := remainingByMask(others, mask)
			next := append([]Meld(nil), melds...)
			next[mi] = updated
			nm, lo, ok := partitionForKnock(rest, next, owner, rs)
			if ok {
				step := LayoffStep{MeldID: m.ID, Cards: append([]Card(nil), group...)}
				return nm, append([]LayoffStep{step}, lo...), true
			}
		}
	}

	return nil, nil, false
}

func remainingByMask(others []Card, mask int) []Card {
	out := make([]Card, 0, len(others))
	for i := 0; i < len(others); i++ {
		if mask&(1<<i) == 0 {
			out = append(out, others[i])
		}
	}
	return out
}

// CanAutoKnock is a thin existence check used by the room view to flag the
// "นอค" button as enabled. It does not retain the plan.
func CanAutoKnock(gs *GameState, p int) bool {
	_, ok := SolveAutoKnock(gs, p)
	return ok
}
