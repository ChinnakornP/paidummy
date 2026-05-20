package game

import (
	"errors"
	"testing"
)

func TestParseCardRoundTripAndErrors(t *testing.T) {
	for _, s := range []string{"AS", "TD", "2C", "KH", "QS"} {
		c := MustCard(s)
		if c.String() != s {
			t.Errorf("round trip %s -> %s", s, c.String())
		}
	}
	for _, bad := range []string{"", "X", "1S", "AX", "ASD"} {
		if _, err := ParseCard(bad); err == nil {
			t.Errorf("ParseCard(%q) should fail", bad)
		}
	}
}

func TestStringers(t *testing.T) {
	if PhaseDraw.String() != "draw" || PhaseMeld.String() != "meld" ||
		PhaseRoundOver.String() != "round_over" || PhaseWaiting.String() != "waiting" {
		t.Error("Phase.String mismatch")
	}
	if MeldRun.String() != "run" || MeldSet.String() != "set" {
		t.Error("MeldKind.String mismatch")
	}
}

func TestEngineMeldLayoffDrawDiscardPaths(t *testing.T) {
	e := Engine{}
	rs := DefaultRuleSet()
	gs, _, _ := e.Start([]string{"A", "B"}, rs, 4)

	// Give player 0 a controlled hand and drive a full meld+layoff+discard turn.
	gs.Phase = PhaseMeld
	gs.Turn = 0
	gs.FirstMove = false
	gs.HeadCard = MustCard("9C")
	gs.HeadOwner = -1
	gs.Players[0].Hand = cards("9C", "9D", "9H", "5S", "6S", "7S", "8S", "QH")

	ev, err := e.ApplyAction(gs, 0, Action{Type: ActMeld, Cards: cards("9C", "9D", "9H")})
	if err != nil || ev[0].Type != EvtMelded {
		t.Fatalf("meld failed: %v", err)
	}
	if gs.HeadOwner != 0 {
		t.Fatalf("head card not absorbed, owner=%d", gs.HeadOwner)
	}
	if !gs.Players[0].Produced {
		t.Fatal("Produced not set after meld")
	}
	if _, err := e.ApplyAction(gs, 0, Action{Type: ActMeld, Cards: cards("5S", "6S", "7S")}); err != nil {
		t.Fatalf("second meld failed: %v", err)
	}
	runID := gs.Melds[1].ID
	if _, err := e.ApplyAction(gs, 0, Action{Type: ActLayOff, MeldID: runID, Cards: cards("8S")}); err != nil {
		t.Fatalf("layoff failed: %v", err)
	}
	if len(gs.Melds[1].Cards) != 4 {
		t.Fatalf("layoff did not extend run: %v", gs.Melds[1].Cards)
	}
	// Bad meld from cards not held.
	if _, err := e.ApplyAction(gs, 0, Action{Type: ActMeld, Cards: cards("2D", "2H", "2S")}); !errors.Is(err, ErrCardNotHeld) {
		t.Fatalf("melding unheld cards: %v", err)
	}
	// Layoff to unknown meld.
	if _, err := e.ApplyAction(gs, 0, Action{Type: ActLayOff, MeldID: "zzz", Cards: cards("QH")}); !errors.Is(err, ErrNoSuchMeld) {
		t.Fatalf("layoff unknown meld: %v", err)
	}
	// Discard remaining QH -> turn passes to player 1, who then "เก็บ"s the
	// QH by combining it with QC+QD from hand into a Q-set meld.
	if _, err := e.ApplyAction(gs, 0, Action{Type: ActDiscard, Card: MustCard("QH")}); err != nil {
		t.Fatalf("discard failed: %v", err)
	}
	if gs.Turn != 1 || gs.Phase != PhaseDraw {
		t.Fatalf("turn/phase after discard: %d/%v", gs.Turn, gs.Phase)
	}
	// Seed player 1 so the pickup forms a valid meld.
	gs.Players[1].Hand = cards("QC", "QD", "5H", "5S")
	melds := len(gs.Melds)

	// Empty-pickup is rejected (no supporting hand cards offered).
	if _, err := e.ApplyAction(gs, 1, Action{Type: ActDrawDiscard}); !errors.Is(err, ErrPickupNeedsMeld) {
		t.Fatalf("empty pickup must require a meld: %v", err)
	}
	// Wrong supporting cards (don't form a meld with QH) are rejected.
	if _, err := e.ApplyAction(gs, 1, Action{Type: ActDrawDiscard, Cards: cards("5H", "5S")}); !errors.Is(err, ErrPickupNeedsMeld) {
		t.Fatalf("invalid meld pickup must be rejected: %v", err)
	}
	ev, err = e.ApplyAction(gs, 1, Action{Type: ActDrawDiscard, Cards: cards("QC", "QD")})
	if err != nil {
		t.Fatalf("valid pickup failed: %v", err)
	}
	if len(ev) != 2 || ev[0].Type != EvtDrewDiscard || ev[1].Type != EvtMelded {
		t.Fatalf("expected drew_discard+melded, got %+v", ev)
	}
	// QH must NOT enter the hand — it goes straight to the new meld.
	for _, c := range gs.Players[1].Hand {
		if c == MustCard("QH") {
			t.Fatal("picked card leaked into hand")
		}
	}
	if len(gs.Melds) != melds+1 || len(gs.Melds[melds].Cards) != 3 {
		t.Fatalf("expected one new 3-card meld, got %d melds", len(gs.Melds))
	}
}

func TestDrawDiscardEmptyRejected(t *testing.T) {
	e := Engine{}
	gs, _, _ := e.Start([]string{"A", "B"}, DefaultRuleSet(), 6)
	gs.FirstMove = false
	if _, err := e.ApplyAction(gs, 0, Action{Type: ActDrawDiscard}); !errors.Is(err, ErrEmptyDiscard) {
		t.Fatalf("empty discard draw must fail: %v", err)
	}
}

func TestIsSpeto(t *testing.T) {
	rs := DefaultRuleSet()
	if !MustCard("2C").IsSpeto(rs) || !MustCard("QS").IsSpeto(rs) {
		t.Error("2C and QS must be speto")
	}
	if MustCard("2D").IsSpeto(rs) {
		t.Error("2D must not be speto")
	}
}
