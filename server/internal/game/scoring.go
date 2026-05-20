package game

// ScoreBreakdown is the per-player decomposition of a round score. It is also
// what gets persisted (as JSON) to round_scores.breakdown.
type ScoreBreakdown struct {
	PlayerID       string `json:"player_id"`
	MeldPoints     int    `json:"meld_points"`
	HeadBonus      int    `json:"head_bonus"`
	KnockBonus     int    `json:"knock_bonus"`
	KnockCardBonus int    `json:"knock_card_bonus"`
	HandPenalty    int    `json:"hand_penalty"` // <= 0
	Total          int    `json:"total"`
}

// meldPoints sums the scoring value of a meld's cards, honoring Ace-high for
// runs that terminate Q-K-A and Speto values.
func meldPoints(m Meld, rs RuleSet) int {
	sum := 0
	for _, c := range m.Cards {
		aceHigh := m.Kind == MeldRun && m.AceHigh && c.Rank == Ace
		sum += c.Points(rs, aceHigh)
	}
	return sum
}

// ScoreRound computes every player's score for a finished round. Index of the
// returned slice aligns with gs.Players. It is pure and reads only gs.RuleSet.
func ScoreRound(gs *GameState) []ScoreBreakdown {
	rs := gs.RuleSet
	out := make([]ScoreBreakdown, len(gs.Players))
	for i := range gs.Players {
		out[i].PlayerID = gs.Players[i].ID
	}

	for _, m := range gs.Melds {
		if m.Owner >= 0 && m.Owner < len(out) {
			out[m.Owner].MeldPoints += meldPoints(m, rs)
		}
	}

	if gs.HeadOwner >= 0 && gs.HeadOwner < len(out) {
		out[gs.HeadOwner].HeadBonus = rs.HeadCardBonus
	}

	if gs.Knocker >= 0 && gs.Knocker < len(out) {
		base := rs.KnockBonus
		if gs.KnockDark {
			base *= rs.DarkKnockMult
		}
		if gs.KnockSuit {
			base *= rs.SameSuitKnockMult
		}
		out[gs.Knocker].KnockBonus = base
		out[gs.Knocker].KnockCardBonus = rs.KnockCardBonus
	}

	for i := range gs.Players {
		pen := 0
		for _, c := range gs.Players[i].Hand {
			pen += rs.HandCardPenalty(c, rs)
		}
		out[i].HandPenalty = -pen
	}

	for i := range out {
		out[i].Total = out[i].MeldPoints + out[i].HeadBonus +
			out[i].KnockBonus + out[i].KnockCardBonus + out[i].HandPenalty
	}
	return out
}
