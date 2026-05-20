package room

import "github.com/andaseacode/paidummy-server/internal/game"

// playerPublic is the publicly visible part of a seat (never the hand cards).
type playerPublic struct {
	Seat      int    `json:"seat"`
	Name      string `json:"name"`
	Ready     bool   `json:"ready"`
	HandCount int    `json:"hand_count"`
	Connected bool   `json:"connected"`
	Coins     int64  `json:"coins"`
}

type meldView struct {
	ID    string   `json:"id"`
	Kind  string   `json:"kind"`
	Cards []string `json:"cards"`
	Owner int      `json:"owner"`
}

// stateView is what a single viewer is allowed to see. Only YourHand is
// private; every other player's cards are exposed solely as a count. This is
// the single chokepoint that makes hand leakage structurally impossible.
type stateView struct {
	RoomID         string `json:"room_id"`
	Bet            int    `json:"bet"`
	Started        bool   `json:"started"`
	CountdownEndMs int64  `json:"countdown_end_ms"` // pre-start countdown
	TurnEndMs      int64  `json:"turn_end_ms"`      // active turn shot clock
	Phase          string `json:"phase"`
	Turn        int            `json:"turn"`
	YourSeat    int            `json:"your_seat"`
	Players     []playerPublic `json:"players"`
	YourHand    []string       `json:"your_hand"`
	Melds       []meldView     `json:"melds"`
	DiscardTop  string         `json:"discard_top"`
	DiscardSize int            `json:"discard_size"`
	DiscardPile []string       `json:"discard_pile"` // full sequence, oldest→newest
	DrawCount   int            `json:"draw_count"`
	HeadCard    string         `json:"head_card"`
	MatchScores map[string]int `json:"match_scores"`
	// CanAutoKnock is true iff it's the viewer's turn, the meld phase is
	// active, and the solver can find a full going-out partition of their
	// current hand. The client uses this to light up the "นอค" button.
	CanAutoKnock bool `json:"can_auto_knock"`
}

func cardStrings(cs []game.Card) []string {
	out := make([]string, len(cs))
	for i, c := range cs {
		out[i] = c.String()
	}
	return out
}

// viewFor builds the projection for the seat at index viewer. Caller holds r.mu.
func (r *Room) viewFor(viewer int) stateView {
	var endMs int64
	if r.state == nil && !r.countdownEnd.IsZero() {
		endMs = r.countdownEnd.UnixMilli()
	}
	var turnMs int64
	if r.state != nil && !r.turnEnd.IsZero() {
		turnMs = r.turnEnd.UnixMilli()
	}
	v := stateView{
		RoomID:         r.ID,
		Bet:            r.Bet,
		YourSeat:       viewer,
		Started:        r.state != nil,
		CountdownEndMs: endMs,
		TurnEndMs:      turnMs,
		MatchScores:    map[string]int{},
	}
	for _, s := range r.seats {
		v.MatchScores[s.GuestID] = r.scores[s.GuestID]
	}
	if r.state == nil {
		for i, s := range r.seats {
			v.Players = append(v.Players, playerPublic{
				Seat: i, Name: s.Name, Ready: s.Ready,
				Connected: s.client != nil, Coins: r.coins[s.GuestID],
			})
		}
		v.Phase = "waiting"
		return v
	}
	gs := r.state
	v.Phase = gs.Phase.String()
	v.Turn = gs.Turn
	v.HeadCard = gs.HeadCard.String()
	v.DrawCount = len(gs.DrawPile)
	v.DiscardSize = len(gs.DiscardPile)
	v.DiscardPile = cardStrings(gs.DiscardPile)
	if n := len(gs.DiscardPile); n > 0 {
		v.DiscardTop = gs.DiscardPile[n-1].String()
	}
	for i, s := range r.seats {
		v.Players = append(v.Players, playerPublic{
			Seat: i, Name: s.Name, Ready: s.Ready,
			HandCount: len(gs.Players[i].Hand), Connected: s.client != nil,
			Coins: r.coins[s.GuestID],
		})
	}
	if viewer >= 0 && viewer < len(gs.Players) {
		v.YourHand = cardStrings(gs.Players[viewer].Hand)
	}
	for _, m := range gs.Melds {
		v.Melds = append(v.Melds, meldView{
			ID: m.ID, Kind: m.Kind.String(), Cards: cardStrings(m.Cards), Owner: m.Owner,
		})
	}
	if viewer == gs.Turn && gs.Phase == game.PhaseMeld {
		v.CanAutoKnock = game.CanAutoKnock(gs, viewer)
	}
	return v
}

// roundResult builds the round_result payload. Caller holds r.mu. The round
// is over here, so every player's hand + meld set is revealed alongside the
// score breakdown — the client renders the rich end-of-round dialog from
// this single payload.
func roundResult(r *Room, sb []game.ScoreBreakdown) map[string]any {
	gs := r.state
	rows := make([]map[string]any, 0, len(sb))
	for i, s := range sb {
		row := map[string]any{
			"seat":             i,
			"name":             r.seats[i].Name,
			"total":            s.Total,
			"meld_points":      s.MeldPoints,
			"head_bonus":       s.HeadBonus,
			"knock_bonus":      s.KnockBonus,
			"knock_card_bonus": s.KnockCardBonus,
			"hand_penalty":     s.HandPenalty,
			"dump_penalty":     s.DumpPenalty,
		}
		if gs != nil && i < len(gs.Players) {
			row["hand"] = cardStrings(gs.Players[i].Hand)
			ownedMelds := make([]map[string]any, 0)
			for _, m := range gs.Melds {
				if m.Owner != i {
					continue
				}
				ownedMelds = append(ownedMelds, map[string]any{
					"id":    m.ID,
					"kind":  m.Kind.String(),
					"cards": cardStrings(m.Cards),
				})
			}
			row["melds"] = ownedMelds
		}
		rows = append(rows, row)
	}
	reason, knocker := "", -1
	if gs != nil {
		reason = gs.EndReason
		knocker = gs.Knocker
	}
	return map[string]any{"reason": reason, "knocker": knocker, "scores": rows}
}
