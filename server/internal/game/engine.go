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

	// The face-up "head" card is laid as the bottom (oldest) of the discard
	// pile so it's pickable like any other discard. HeadCard is still tracked
	// separately so the +50 เกิดหัว bonus can be awarded when whoever picks
	// it up melds it.
	gs := &GameState{
		Players:     make([]Player, n),
		Turn:        0,
		Phase:       PhaseDraw,
		DrawPile:    draw,
		DiscardPile: []Card{head},
		// The head card sits at the bottom of the discard pile but no player
		// dealt it — store -1 to mean "no one is on the hook for a dummy on
		// this card" so the dummy attribution logic treats picking up the
		// head card as a no-op for penalties.
		DiscardedBy:   []int{-1},
		HeadCard:      head,
		HeadOwner:     -1,
		Seed:          seed,
		FirstMove:     true,
		Knocker:       -1,
		RuleSet:       rs,
		DumpPenalties: make([]int, n),
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
		// "เก็บ" rule: the picked card must immediately combine with cards in
		// the hand to form a valid meld; the picked card and the supporting
		// hand cards leave the discard/hand → table in one action.
		//
		// a.Card  — optional target. Zero-value picks the top of the pile.
		//           If specified, the engine finds it in the pile (closest to
		//           top wins on ties); cards *newer* than the target (above
		//           it) are pulled into the player's hand as the cost of
		//           reaching that deep.
		// a.Cards — supporting hand cards. The meld is built from
		//           a.Cards ∪ {target}.
		if gs.FirstMove {
			return nil, ErrMustDrawDeck
		}
		if len(gs.DiscardPile) == 0 {
			return nil, ErrEmptyDiscard
		}
		// Locate target.
		targetIdx := len(gs.DiscardPile) - 1
		if a.Card != (Card{}) {
			targetIdx = -1
			for i := len(gs.DiscardPile) - 1; i >= 0; i-- {
				if gs.DiscardPile[i] == a.Card {
					targetIdx = i
					break
				}
			}
			if targetIdx == -1 {
				return nil, ErrCardNotHeld
			}
		}
		target := gs.DiscardPile[targetIdx]
		if len(a.Cards) < gs.RuleSet.MinMeldLen-1 {
			return nil, ErrPickupNeedsMeld
		}
		// a.Cards is the supporting set for the meld. It may mix hand cards
		// and cards from the pile above the target — the engine sorts them
		// out so the UI can simply say "these cards go in the meld".
		above := gs.DiscardPile[targetIdx+1:]
		usedAbove := make([]bool, len(above))
		var fromPile, fromHand []Card
		for _, c := range a.Cards {
			matched := -1
			for i, ac := range above {
				if !usedAbove[i] && ac == c {
					matched = i
					break
				}
			}
			if matched >= 0 {
				usedAbove[matched] = true
				fromPile = append(fromPile, c)
			} else {
				fromHand = append(fromHand, c)
			}
		}
		if !gs.handContains(p, fromHand) {
			return nil, ErrCardNotHeld
		}

		combined := make([]Card, 0, len(a.Cards)+1)
		combined = append(combined, a.Cards...)
		combined = append(combined, target)
		m, err := NewMeld(gs.nextMeldID(), combined, p, gs.RuleSet)
		if err != nil {
			return nil, ErrPickupNeedsMeld
		}
		// Unclaimed above-target cards fall into the player's hand (the cost
		// of reaching past them). Iteration order keeps the original pile
		// order so the player can read it sensibly.
		var extras []Card
		for i, c := range above {
			if !usedAbove[i] {
				extras = append(extras, c)
			}
		}
		// ทิ้งดัมมี่: the original discarder of the picked target now
		// owes a DumpPenalty (an opponent successfully picked their discard
		// up into a meld). The head card was placed by no one (-1), so it
		// can't trigger the penalty. Same-player pickups (uncommon, only on
		// pile cards they discarded themselves) also don't trigger.
		if targetIdx < len(gs.DiscardedBy) {
			if dumper := gs.DiscardedBy[targetIdx]; dumper >= 0 && dumper != p {
				gs.ensureDumpPenaltiesLen()
				gs.DumpPenalties[dumper] += gs.RuleSet.DumpPenalty
			}
		}
		gs.DiscardPile = gs.DiscardPile[:targetIdx] // drops target + all above
		if targetIdx < len(gs.DiscardedBy) {
			gs.DiscardedBy = gs.DiscardedBy[:targetIdx]
		}
		gs.Players[p].Hand = append(gs.Players[p].Hand, extras...)
		gs.removeFromHand(p, fromHand)
		gs.Melds = append(gs.Melds, m)
		gs.Players[p].Melds = append(gs.Players[p].Melds, m.ID)
		gs.Players[p].Produced = true
		gs.absorbHead(m.Cards, p)
		gs.Phase = PhaseMeld
		return []Event{
			{Type: EvtDrewDiscard, Player: p, Card: target},
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
	case ActAutoKnock:
		return e.applyAutoKnock(gs, p)
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

// applyAutoKnock asks the solver for any going-out partition of the player's
// hand. On success it materialises every new meld + layoff and finalises the
// knock — emitting one EvtMelded / EvtLaidOff per planned step so the room
// can broadcast the full sequence to viewers. Dark-knock cannot be claimed
// via auto-knock (the explicit flag belongs to ActKnock).
func (e Engine) applyAutoKnock(gs *GameState, p int) ([]Event, error) {
	plan, ok := SolveAutoKnock(gs, p)
	if !ok {
		return nil, ErrBadKnock
	}
	events := make([]Event, 0, len(plan.NewMelds)+len(plan.Layoffs)+2)
	for _, group := range plan.NewMelds {
		m, err := NewMeld(gs.nextMeldID(), group, p, gs.RuleSet)
		if err != nil {
			return nil, err
		}
		gs.removeFromHand(p, group)
		gs.Melds = append(gs.Melds, m)
		gs.Players[p].Melds = append(gs.Players[p].Melds, m.ID)
		gs.Players[p].Produced = true
		gs.absorbHead(m.Cards, p)
		events = append(events, Event{Type: EvtMelded, Player: p, Cards: m.Cards, MeldID: m.ID})
	}
	for _, step := range plan.Layoffs {
		mi := gs.findMeld(step.MeldID)
		if mi == -1 {
			return nil, ErrNoSuchMeld
		}
		updated, err := canLayOff(gs.Melds[mi], step.Cards, gs.RuleSet)
		if err != nil {
			return nil, err
		}
		gs.removeFromHand(p, step.Cards)
		gs.Melds[mi] = updated
		gs.absorbHead(step.Cards, gs.Melds[mi].Owner)
		events = append(events, Event{Type: EvtLaidOff, Player: p, Cards: step.Cards, MeldID: step.MeldID})
	}
	// Finalise the knock — the solver guarantees the knock card is the last
	// remaining card in hand at this point.
	gs.removeFromHand(p, []Card{plan.KnockCard})
	gs.RoundOver = true
	gs.Phase = PhaseRoundOver
	gs.EndReason = "knock"
	gs.Knocker = p
	gs.KnockSuit = knockSuitBoard(gs, p, plan.KnockCard)
	events = append(events,
		Event{Type: EvtKnocked, Player: p, Card: plan.KnockCard},
		Event{Type: EvtRoundOver, Reason: "knock"},
	)
	return events, nil
}

func (Engine) applyDiscard(gs *GameState, p int, a Action) ([]Event, error) {
	if !gs.handContains(p, []Card{a.Card}) {
		return nil, ErrCardNotHeld
	}
	// ทิ้งเต็ม: discarding a card that would have laid off cleanly onto any
	// table meld is a penalised dump (-rs.DumpPenalty for the discarder).
	if isLayableOnAny(gs.Melds, a.Card, gs.RuleSet) {
		gs.ensureDumpPenaltiesLen()
		gs.DumpPenalties[p] += gs.RuleSet.DumpPenalty
	}
	gs.removeFromHand(p, []Card{a.Card})
	gs.DiscardPile = append(gs.DiscardPile, a.Card)
	gs.DiscardedBy = append(gs.DiscardedBy, p)
	gs.Turn = (gs.Turn + 1) % len(gs.Players)
	gs.Phase = PhaseDraw
	gs.Players[gs.Turn].ProducedAtTurnStart = gs.Players[gs.Turn].Produced
	return []Event{
		{Type: EvtDiscarded, Player: p, Card: a.Card},
		{Type: EvtTurnChanged, Player: gs.Turn},
	}, nil
}

// isLayableOnAny reports whether `c` alone would be a valid layoff onto any
// existing meld in `melds`. Used to flag a ทิ้งเต็ม discard.
func isLayableOnAny(melds []Meld, c Card, rs RuleSet) bool {
	for _, m := range melds {
		if _, err := canLayOff(m, []Card{c}, rs); err == nil {
			return true
		}
	}
	return false
}

// ensureDumpPenaltiesLen lazily sizes the slice — older snapshots persisted
// before the field existed rehydrate with a nil slice; first write expands.
func (gs *GameState) ensureDumpPenaltiesLen() {
	if len(gs.DumpPenalties) < len(gs.Players) {
		grown := make([]int, len(gs.Players))
		copy(grown, gs.DumpPenalties)
		gs.DumpPenalties = grown
	}
}
