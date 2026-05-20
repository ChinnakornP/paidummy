package game

import (
	"errors"
	"testing"
)

func TestStartDealsRound(t *testing.T) {
	rs := DefaultRuleSet()
	gs, ev, err := Engine{}.Start([]string{"A", "B"}, rs, 7)
	if err != nil {
		t.Fatal(err)
	}
	if gs.Turn != 0 || gs.Phase != PhaseDraw || !gs.FirstMove {
		t.Fatalf("bad initial state: turn=%d phase=%v first=%v", gs.Turn, gs.Phase, gs.FirstMove)
	}
	for i, p := range gs.Players {
		if len(p.Hand) != 11 {
			t.Fatalf("player %d hand=%d want 11", i, len(p.Hand))
		}
	}
	if len(ev) != 1 || ev[0].Type != EvtTurnChanged {
		t.Fatalf("expected initial turn event, got %+v", ev)
	}
}

func TestStartRejectsBadPlayerCount(t *testing.T) {
	if _, _, err := (Engine{}).Start([]string{"A"}, DefaultRuleSet(), 1); err == nil {
		t.Fatal("1 player must be rejected")
	}
}

func TestTurnOrderAndPhaseGuards(t *testing.T) {
	e := Engine{}
	gs, _, _ := e.Start([]string{"A", "B"}, DefaultRuleSet(), 3)

	if _, err := e.ApplyAction(gs, 1, Action{Type: ActDrawDeck}); !errors.Is(err, ErrNotYourTurn) {
		t.Fatalf("out-of-turn: got %v", err)
	}
	if _, err := e.ApplyAction(gs, 0, Action{Type: ActDrawDiscard}); !errors.Is(err, ErrMustDrawDeck) {
		t.Fatalf("first move must draw deck: got %v", err)
	}
	if _, err := e.ApplyAction(gs, 0, Action{Type: ActDiscard, Card: gs.Players[0].Hand[0]}); !errors.Is(err, ErrWrongPhase) {
		t.Fatalf("discard before draw: got %v", err)
	}
	before := len(gs.Players[0].Hand)
	if _, err := e.ApplyAction(gs, 0, Action{Type: ActDrawDeck}); err != nil {
		t.Fatal(err)
	}
	if gs.Phase != PhaseMeld || len(gs.Players[0].Hand) != before+1 || gs.FirstMove {
		t.Fatalf("after deck draw: phase=%v hand=%d first=%v", gs.Phase, len(gs.Players[0].Hand), gs.FirstMove)
	}
	discard := gs.Players[0].Hand[0]
	if _, err := e.ApplyAction(gs, 0, Action{Type: ActDiscard, Card: discard}); err != nil {
		t.Fatal(err)
	}
	if gs.Turn != 1 || gs.Phase != PhaseDraw {
		t.Fatalf("turn did not advance: turn=%d phase=%v", gs.Turn, gs.Phase)
	}
	top, _ := gs.topDiscard()
	if top != discard {
		t.Fatalf("discard top=%s want %s", top, discard)
	}
}

func TestDeckExhaustEndsRound(t *testing.T) {
	e := Engine{}
	gs, _, _ := e.Start([]string{"A", "B"}, DefaultRuleSet(), 5)
	gs.DrawPile = nil // force exhaustion
	ev, err := e.ApplyAction(gs, 0, Action{Type: ActDrawDeck})
	if err != nil {
		t.Fatal(err)
	}
	if !gs.RoundOver || gs.EndReason != "deck_exhaust" {
		t.Fatalf("round not ended by exhaust: over=%v reason=%q", gs.RoundOver, gs.EndReason)
	}
	if len(ev) != 1 || ev[0].Type != EvtRoundOver {
		t.Fatalf("expected round-over event, got %+v", ev)
	}
	if _, err := e.ApplyAction(gs, 0, Action{Type: ActDrawDeck}); !errors.Is(err, ErrRoundOver) {
		t.Fatalf("actions after round over must fail: %v", err)
	}
}

func TestKnockFlowAndScoring(t *testing.T) {
	e := Engine{}
	rs := DefaultRuleSet()
	gs, _, _ := e.Start([]string{"A", "B"}, rs, 9)
	// Drive directly to a knockable position for player 0.
	gs.Phase = PhaseMeld
	gs.Turn = 0
	knock := MustCard("KD")
	gs.Players[0].Hand = []Card{knock}
	gs.Players[0].Produced = true
	gs.Melds = []Meld{{ID: "m1", Kind: MeldSet, Cards: cards("9C", "9D", "9H"), Owner: 0}}
	gs.Players[0].Melds = []string{"m1"}

	ev, err := e.ApplyAction(gs, 0, Action{Type: ActKnock, Card: knock})
	if err != nil {
		t.Fatalf("knock failed: %v", err)
	}
	if !gs.RoundOver || gs.Knocker != 0 || gs.EndReason != "knock" {
		t.Fatalf("knock state wrong: %+v", gs)
	}
	if len(ev) != 2 || ev[0].Type != EvtKnocked || ev[1].Type != EvtRoundOver {
		t.Fatalf("knock events wrong: %+v", ev)
	}
	if len(gs.Players[0].Hand) != 0 {
		t.Fatalf("knocker hand not emptied: %v", gs.Players[0].Hand)
	}
	sb := ScoreRound(gs)
	// 9-set = 27, standard knock 50 + knock-card 50 = 127.
	if sb[0].Total != 127 {
		t.Fatalf("knocker total = %d want 127 (%+v)", sb[0].Total, sb[0])
	}
}

func TestKnockRequiresExactlyKnockCard(t *testing.T) {
	e := Engine{}
	gs, _, _ := e.Start([]string{"A", "B"}, DefaultRuleSet(), 2)
	gs.Phase = PhaseMeld
	gs.Turn = 0
	gs.Players[0].Hand = cards("KD", "5C")
	if _, err := e.ApplyAction(gs, 0, Action{Type: ActKnock, Card: MustCard("KD")}); !errors.Is(err, ErrBadKnock) {
		t.Fatalf("knock with extra cards must fail: %v", err)
	}
}
