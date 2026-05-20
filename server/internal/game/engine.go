package game

import (
	"errors"
	"fmt"
)

// Engine is a stateless executor of game rules. All state lives in *GameState;
// Engine only validates and mutates it. No I/O, no goroutines, no time.
type Engine struct{}

var (
	ErrRoundOver    = errors.New("round is over")
	ErrNotYourTurn  = errors.New("not your turn")
	ErrWrongPhase   = errors.New("action not allowed in this phase")
	ErrMustDrawDeck = errors.New("first move of the round must draw from the deck")
	ErrEmptyDiscard = errors.New("discard pile is empty")
	ErrCardNotHeld     = errors.New("card not in hand")
	ErrBadKnock        = errors.New("knock requires every card melded except the knock card")
	ErrNoSuchMeld      = errors.New("no such table meld")
	ErrPickupNeedsMeld = errors.New("picking up the discard requires forming a valid meld with cards from your hand")
)

// Start deals a fresh round. playerIDs order is seating order; player 0 leads
// and (per Thai Dummy) must take their first card from the deck.
func (Engine) Start(playerIDs []string, rs RuleSet, seed int64) (*GameState, []Event, error) {
	n := len(playerIDs)
	if n < rs.MinPlayers || n > rs.MaxPlayers {
		return nil, nil, fmt.Errorf("need %d-%d players, got %d", rs.MinPlayers, rs.MaxPlayers, n)
	}
	deck := Shuffle(NewDeck(), seed)
	hands, head, draw := Deal(deck, n, rs)

	gs := &GameState{
		Players:     make([]Player, n),
		Turn:        0,
		Phase:       PhaseDraw,
		DrawPile:    draw,
		DiscardPile: nil,
		HeadCard:    head,
		HeadOwner:   -1,
		Seed:        seed,
		FirstMove:   true,
		Knocker:     -1,
		RuleSet:     rs,
	}
	for i, id := range playerIDs {
		gs.Players[i] = Player{ID: id, Hand: hands[i]}
	}
	return gs, []Event{{Type: EvtTurnChanged, Player: 0}}, nil
}

// ApplyAction validates and applies a single move by playerIdx, returning the
// resulting events. It is the only mutator of GameState.
func (e Engine) ApplyAction(gs *GameState, playerIdx int, a Action) ([]Event, error) {
	if gs.RoundOver {
		return nil, ErrRoundOver
	}
	if playerIdx != gs.Turn {
		return nil, ErrNotYourTurn
	}
	switch gs.Phase {
	case PhaseDraw:
		return e.applyDraw(gs, playerIdx, a)
	case PhaseMeld:
		return e.applyMeldPhase(gs, playerIdx, a)
	default:
		return nil, ErrWrongPhase
	}
}

func (Engine) applyDraw(gs *GameState, p int, a Action) ([]Event, error) {
	switch a.Type {
	case ActDrawDeck:
		gs.FirstMove = false
		if len(gs.DrawPile) == 0 {
			gs.RoundOver = true
			gs.Phase = PhaseRoundOver
			gs.EndReason = "deck_exhaust"
			return []Event{{Type: EvtRoundOver, Reason: "deck_exhaust"}}, nil
		}
		c := gs.DrawPile[0]
		gs.DrawPile = gs.DrawPile[1:]
		gs.Players[p].Hand = append(gs.Players[p].Hand, c)
		gs.Phase = PhaseMeld
		return []Event{{Type: EvtDrewDeck, Player: p, Card: c}}, nil

	case ActDrawDiscard:
		// "เก็บ" rule: a player may only pick up the discard top if it
		// combines with cards in their hand to form a valid meld, and that
		// meld is committed immediately (the picked card and the supporting
		// hand cards leave hand → table). a.Cards is the supporting set.
		// Example: hand 3,A,7♠,8♠,9♠ — picking 7♣ is invalid (suit/run
		// mismatch); picking 7♠ requires Cards=[8♠,9♠] so the meld 7-8-9♠
		// is laid down in the same action.
		// // TODO(spec): some houses also allow picking to lay off onto an
		// existing table meld; not supported yet.
		if gs.FirstMove {
			return nil, ErrMustDrawDeck
		}
		top, ok := gs.topDiscard()
		if !ok {
			return nil, ErrEmptyDiscard
		}
		if len(a.Cards) < gs.RuleSet.MinMeldLen-1 {
			return nil, ErrPickupNeedsMeld
		}
		if !gs.handContains(p, a.Cards) {
			return nil, ErrCardNotHeld
		}
		combined := make([]Card, 0, len(a.Cards)+1)
		combined = append(combined, a.Cards...)
		combined = append(combined, top)
		m, err := NewMeld(gs.nextMeldID(), combined, p, gs.RuleSet)
		if err != nil {
			return nil, ErrPickupNeedsMeld
		}
		// Commit atomically — pop discard, remove supporting cards, expose meld.
		gs.DiscardPile = gs.DiscardPile[:len(gs.DiscardPile)-1]
		gs.removeFromHand(p, a.Cards)
		gs.Melds = append(gs.Melds, m)
		gs.Players[p].Melds = append(gs.Players[p].Melds, m.ID)
		gs.Players[p].Produced = true
		gs.absorbHead(m.Cards, p)
		gs.Phase = PhaseMeld
		return []Event{
			{Type: EvtDrewDiscard, Player: p, Card: top},
			{Type: EvtMelded, Player: p, Cards: m.Cards, MeldID: m.ID},
		}, nil

	default:
		return nil, ErrWrongPhase
	}
}

func (e Engine) applyMeldPhase(gs *GameState, p int, a Action) ([]Event, error) {
	switch a.Type {
	case ActMeld:
		return e.applyMeld(gs, p, a)
	case ActLayOff:
		return e.applyLayOff(gs, p, a)
	case ActKnock:
		return e.applyKnock(gs, p, a)
	case ActDiscard:
		return e.applyDiscard(gs, p, a)
	default:
		return nil, ErrWrongPhase
	}
}

func (gs *GameState) nextMeldID() string {
	gs.NextMeldSeq++
	return fmt.Sprintf("m%d", gs.NextMeldSeq)
}

// absorbHead records head-card ownership the first time the เกิดหัว card
// becomes part of any meld.
func (gs *GameState) absorbHead(cards []Card, owner int) {
	if gs.HeadOwner != -1 {
		return
	}
	for _, c := range cards {
		if c == gs.HeadCard {
			gs.HeadOwner = owner
			return
		}
	}
}

func (Engine) applyMeld(gs *GameState, p int, a Action) ([]Event, error) {
	if !gs.handContains(p, a.Cards) {
		return nil, ErrCardNotHeld
	}
	m, err := NewMeld(gs.nextMeldID(), a.Cards, p, gs.RuleSet)
	if err != nil {
		return nil, err
	}
	gs.removeFromHand(p, a.Cards)
	gs.Melds = append(gs.Melds, m)
	gs.Players[p].Melds = append(gs.Players[p].Melds, m.ID)
	gs.Players[p].Produced = true
	gs.absorbHead(m.Cards, p)
	return []Event{{Type: EvtMelded, Player: p, Cards: m.Cards, MeldID: m.ID}}, nil
}

func (Engine) applyLayOff(gs *GameState, p int, a Action) ([]Event, error) {
	mi := gs.findMeld(a.MeldID)
	if mi == -1 {
		return nil, ErrNoSuchMeld
	}
	if !gs.handContains(p, a.Cards) {
		return nil, ErrCardNotHeld
	}
	updated, err := canLayOff(gs.Melds[mi], a.Cards, gs.RuleSet)
	if err != nil {
		return nil, err
	}
	gs.removeFromHand(p, a.Cards)
	gs.Melds[mi] = updated
	gs.absorbHead(a.Cards, gs.Melds[mi].Owner)
	return []Event{{Type: EvtLaidOff, Player: p, Cards: a.Cards, MeldID: a.MeldID}}, nil
}

// knockSuitBoard reports whether every meld owned by p plus the knock card are
// all the same suit (น็อคสี).
func knockSuitBoard(gs *GameState, p int, knock Card) bool {
	suit := knock.Suit
	any := false
	for _, m := range gs.Melds {
		if m.Owner != p {
			continue
		}
		any = true
		for _, c := range m.Cards {
			if c.Suit != suit {
				return false
			}
		}
	}
	return any
}

func (Engine) applyKnock(gs *GameState, p int, a Action) ([]Event, error) {
	hand := gs.Players[p].Hand
	// Going out: after melds are on the table the only card left is the knock
	// card. // TODO(spec): some houses allow knocking with a layable last card.
	if len(hand) != 1 || hand[0] != a.Card {
		return nil, ErrBadKnock
	}
	gs.removeFromHand(p, []Card{a.Card})
	gs.RoundOver = true
	gs.Phase = PhaseRoundOver
	gs.EndReason = "knock"
	gs.Knocker = p
	// Dark/หลับ: knocked without having produced any meld before this turn.
	gs.KnockDark = a.Dark && !gs.Players[p].ProducedAtTurnStart
	gs.KnockSuit = knockSuitBoard(gs, p, a.Card)
	return []Event{
		{Type: EvtKnocked, Player: p, Card: a.Card},
		{Type: EvtRoundOver, Reason: "knock"},
	}, nil
}

func (Engine) applyDiscard(gs *GameState, p int, a Action) ([]Event, error) {
	if !gs.handContains(p, []Card{a.Card}) {
		return nil, ErrCardNotHeld
	}
	gs.removeFromHand(p, []Card{a.Card})
	gs.DiscardPile = append(gs.DiscardPile, a.Card)
	gs.Turn = (gs.Turn + 1) % len(gs.Players)
	gs.Phase = PhaseDraw
	gs.Players[gs.Turn].ProducedAtTurnStart = gs.Players[gs.Turn].Produced
	return []Event{
		{Type: EvtDiscarded, Player: p, Card: a.Card},
		{Type: EvtTurnChanged, Player: gs.Turn},
	}, nil
}
