package game

import "testing"

// TestSolveAutoKnockNewMelds: a hand that partitions cleanly into two new
// melds plus a single knock card finds a plan.
func TestSolveAutoKnockNewMelds(t *testing.T) {
	gs := &GameState{
		RuleSet: DefaultRuleSet(),
		Players: []Player{{Hand: cards("AS", "AH", "AC", "2D", "3D", "4D", "9C")}},
	}
	plan, ok := SolveAutoKnock(gs, 0)
	if !ok {
		t.Fatalf("expected a knock plan, got none")
	}
	if plan.KnockCard != MustCard("9C") {
		t.Fatalf("knock card = %s, want 9C", plan.KnockCard)
	}
	if len(plan.NewMelds) != 2 {
		t.Fatalf("expected 2 new melds, got %d", len(plan.NewMelds))
	}
}

// TestSolveAutoKnockWithLayoff: an existing table run "5D 6D 7D" absorbs the
// player's 4D and 8D as layoffs, freeing the rest of the hand into one new
// set + a knock card.
func TestSolveAutoKnockWithLayoff(t *testing.T) {
	rs := DefaultRuleSet()
	gs := &GameState{
		RuleSet: rs,
		Players: []Player{{Hand: cards("4D", "8D", "AS", "AH", "AC", "2C")}},
	}
	existing, err := NewMeld("m1", cards("5D", "6D", "7D"), 1, rs)
	if err != nil {
		t.Fatalf("setup meld: %v", err)
	}
	gs.Melds = []Meld{existing}

	plan, ok := SolveAutoKnock(gs, 0)
	if !ok {
		t.Fatalf("expected a knock plan with layoffs, got none")
	}
	if plan.KnockCard != MustCard("2C") {
		t.Fatalf("knock card = %s, want 2C", plan.KnockCard)
	}
	if len(plan.NewMelds) != 1 {
		t.Fatalf("expected 1 new meld (AAA), got %d", len(plan.NewMelds))
	}
	if len(plan.Layoffs) == 0 {
		t.Fatalf("expected at least one layoff onto m1, got none")
	}
}

// TestSolveAutoKnockImpossible: a hand with no valid going-out partition.
func TestSolveAutoKnockImpossible(t *testing.T) {
	gs := &GameState{
		RuleSet: DefaultRuleSet(),
		Players: []Player{{Hand: cards("AS", "5H", "9C", "KD")}},
	}
	if _, ok := SolveAutoKnock(gs, 0); ok {
		t.Fatalf("expected no plan, got one")
	}
}

// TestApplyAutoKnockEndsRound: end-to-end through the engine, the round is
// flagged over with reason=knock and the player's hand is empty.
func TestApplyAutoKnockEndsRound(t *testing.T) {
	e := Engine{}
	rs := DefaultRuleSet()
	gs, _, _ := e.Start([]string{"A", "B"}, rs, 21)
	gs.FirstMove = false
	gs.Turn = 0
	gs.Phase = PhaseMeld
	gs.Players[0].Hand = cards("AS", "AH", "AC", "2D", "3D", "4D", "9C")

	events, err := e.ApplyAction(gs, 0, Action{Type: ActAutoKnock})
	if err != nil {
		t.Fatalf("auto-knock errored: %v", err)
	}
	if !gs.RoundOver || gs.EndReason != "knock" || gs.Knocker != 0 {
		t.Fatalf("round state wrong: over=%v reason=%q knocker=%d",
			gs.RoundOver, gs.EndReason, gs.Knocker)
	}
	if len(gs.Players[0].Hand) != 0 {
		t.Fatalf("hand should be empty, got %v", gs.Players[0].Hand)
	}
	hasKnock, hasRoundOver := false, false
	for _, ev := range events {
		if ev.Type == EvtKnocked {
			hasKnock = true
		}
		if ev.Type == EvtRoundOver {
			hasRoundOver = true
		}
	}
	if !hasKnock || !hasRoundOver {
		t.Fatalf("missing knock/round-over events: %+v", events)
	}
}
