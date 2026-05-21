package game

// Suggest-a-move ("ช่วยคิด"): a lightweight hint engine layered on the same
// primitives the auto-knock solver and meld validator use. It never mutates
// state — it only inspects the player's hand + the table and recommends one
// next action.

// Suggestion is a single recommended move for the active player.
type Suggestion struct {
	Kind   string   `json:"kind"`              // draw | knock | meld | layoff | discard
	Cards  []string `json:"cards"`             // card codes involved (hand cards)
	MeldID string   `json:"meld_id,omitempty"` // target meld for a layoff
	Reason string   `json:"reason"`            // short Thai explanation
}

func cardCodes(cs []Card) []string {
	out := make([]string, len(cs))
	for i, c := range cs {
		out[i] = c.String()
	}
	return out
}

// SuggestMove returns the single best next action for player p. Priority:
// knock > new meld > layoff > discard-highest. During the draw phase it
// simply nudges the player to draw.
func SuggestMove(gs *GameState, p int) Suggestion {
	if gs == nil || p < 0 || p >= len(gs.Players) {
		return Suggestion{Kind: "draw", Reason: "รอเริ่มเกม"}
	}
	if gs.Phase == PhaseDraw {
		return Suggestion{Kind: "draw", Reason: "จั่วไพ่จากกองก่อน"}
	}
	rs := gs.RuleSet
	hand := gs.Players[p].Hand

	// 1) Going-out plan available → knock.
	if plan, ok := SolveAutoKnock(gs, p); ok {
		return Suggestion{
			Kind:   "knock",
			Cards:  []string{plan.KnockCard.String()},
			Reason: "น็อคได้เลย! กดปุ่มน็อค",
		}
	}

	// 2) A fresh valid meld (smallest legal size) hiding in hand.
	if meld := firstNewMeld(hand, rs); meld != nil {
		return Suggestion{
			Kind:   "meld",
			Cards:  cardCodes(meld),
			Reason: "ลงไพ่ชุดนี้ได้",
		}
	}

	// 3) A single-card layoff onto an existing table meld.
	for _, m := range gs.Melds {
		for _, c := range hand {
			if _, err := canLayOff(m, []Card{c}, rs); err == nil {
				return Suggestion{
					Kind:   "layoff",
					Cards:  []string{c.String()},
					MeldID: m.ID,
					Reason: "ฝากไพ่ใบนี้เข้าชุดบนโต๊ะได้",
				}
			}
		}
	}

	// 4) Nothing to lay → dump the highest-value card to cut hand penalty.
	if worst, ok := highestValueCard(hand, rs); ok {
		return Suggestion{
			Kind:   "discard",
			Cards:  []string{worst.String()},
			Reason: "ทิ้งใบที่แต้มสูงสุดเพื่อลดแต้มติดมือ",
		}
	}
	return Suggestion{Kind: "discard", Reason: "ทิ้งไพ่หนึ่งใบ"}
}

// firstNewMeld returns the lowest-size valid new meld (sets/runs) found in
// the hand, or nil. Tries MinMeldLen-size combinations — hand sizes are
// small (≤12) so the brute force is cheap.
func firstNewMeld(hand []Card, rs RuleSet) []Card {
	n := len(hand)
	k := rs.MinMeldLen
	if k <= 0 || n < k {
		return nil
	}
	idx := make([]int, k)
	for i := range idx {
		idx[i] = i
	}
	for {
		combo := make([]Card, k)
		for i, ix := range idx {
			combo[i] = hand[ix]
		}
		if _, err := NewMeld("suggest", combo, 0, rs); err == nil {
			return combo
		}
		// advance the combination indices (lexicographic)
		i := k - 1
		for i >= 0 && idx[i] == n-k+i {
			i--
		}
		if i < 0 {
			return nil
		}
		idx[i]++
		for j := i + 1; j < k; j++ {
			idx[j] = idx[j-1] + 1
		}
	}
}

// highestValueCard returns the card worth the most penalty points (Ace low),
// the safest single discard when no meld is available.
func highestValueCard(hand []Card, rs RuleSet) (Card, bool) {
	if len(hand) == 0 {
		return Card{}, false
	}
	best := hand[0]
	bestPts := best.Points(rs, false)
	for _, c := range hand[1:] {
		if pts := c.Points(rs, false); pts > bestPts {
			best, bestPts = c, pts
		}
	}
	return best, true
}
