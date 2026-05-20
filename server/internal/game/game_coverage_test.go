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

// TestDrawDiscardTargetWithExtras: when the player picks a card that isn't
// the top of the pile, every newer card (above the target) is pulled into
// their hand as the cost of reaching deep.
func TestDrawDiscardTargetWithExtras(t *testing.T) {
	e := Engine{}
	rs := DefaultRuleSet()
	gs, _, _ := e.Start([]string{"A", "B"}, rs, 11)

	// Plant a deterministic state: it's player 0's turn, phase draw, discard
	// pile is [QH, 5D, 7H, 2C] (oldest→newest). Player wants to pick QH
	// (oldest) and meld it with QC+QS from hand.
	gs.FirstMove = false
	gs.Turn = 0
	gs.Phase = PhaseDraw
	gs.DiscardPile = cards("QH", "5D", "7H", "2C")
	gs.Players[0].Hand = cards("QC", "QS", "KH")
	preHandLen := len(gs.Players[0].Hand)

	ev, err := e.ApplyAction(gs, 0, Action{
		Type:  ActDrawDiscard,
		Card:  MustCard("QH"),
		Cards: cards("QC", "QS"),
	})
	if err != nil {
		t.Fatalf("pick QH failed: %v", err)
	}
	if len(ev) != 2 || ev[0].Type != EvtDrewDiscard || ev[0].Card != MustCard("QH") {
		t.Fatalf("expected drew_discard for QH: %+v", ev)
	}
	if len(gs.DiscardPile) != 0 {
		t.Fatalf("discard pile should be empty, got %v", gs.DiscardPile)
	}
	wantHand := preHandLen + 3 - 2 // +3 extras, -2 used in meld
	if len(gs.Players[0].Hand) != wantHand {
		t.Fatalf("hand len = %d, want %d (extras pulled in)", len(gs.Players[0].Hand), wantHand)
	}
	for _, c := range cards("5D", "7H", "2C") {
		found := false
		for _, h := range gs.Players[0].Hand {
			if h == c {
				found = true
				break
			}
		}
		if !found {
			t.Errorf("extra %s should now be in hand", c)
		}
	}
	if len(gs.Melds) != 1 || len(gs.Melds[0].Cards) != 3 {
		t.Fatalf("expected one 3-card meld, got %v", gs.Melds)
	}
}

// TestDrawDiscardTargetNotInPile: picking a card not present errors out.
func TestDrawDiscardTargetNotInPile(t *testing.T) {
	e := Engine{}
	gs, _, _ := e.Start([]string{"A", "B"}, DefaultRuleSet(), 12)
	gs.FirstMove = false
	gs.Turn = 0
	gs.Phase = PhaseDraw
	gs.DiscardPile = cards("QH")
	gs.Players[0].Hand = cards("QC", "QS")
	if _, err := e.ApplyAction(gs, 0, Action{
		Type:  ActDrawDiscard,
		Card:  MustCard("KC"),
		Cards: cards("QC", "QS"),
	}); !errors.Is(err, ErrCardNotHeld) {
		t.Fatalf("missing target should fail: %v", err)
	}
}

// TestHeadCardSitsOnDiscardAndIsPickable: the face-up head card opens at
// the bottom of the discard pile (so a player can "เก็บ" it on a later
// turn) and triggers the +50 head bonus when melded.
func TestHeadCardSitsOnDiscardAndIsPickable(t *testing.T) {
	e := Engine{}
	rs := DefaultRuleSet()
	gs, _, _ := e.Start([]string{"A", "B"}, rs, 13)

	// Sanity: head is the first (and currently only) discard card.
	if len(gs.DiscardPile) != 1 || gs.DiscardPile[0] != gs.HeadCard {
		t.Fatalf("head should seed discard pile: pile=%v head=%v",
			gs.DiscardPile, gs.HeadCard)
	}
	// HeadOwner unclaimed until someone melds it.
	if gs.HeadOwner != -1 {
		t.Fatalf("HeadOwner pre-pickup = %d, want -1", gs.HeadOwner)
	}

	// Pretend player 0 already had their first draw and now wants to pick
	// the head card. Seed a meld that combines with whatever the head is.
	gs.FirstMove = false
	gs.Turn = 0
	gs.Phase = PhaseDraw
	head := gs.HeadCard
	// Two other cards of the same rank from the other three suits.
	siblings := siblingsOf(head)
	gs.Players[0].Hand = append([]Card{}, siblings...)

	_, err := e.ApplyAction(gs, 0, Action{
		Type:  ActDrawDiscard,
		Card:  head,
		Cards: siblings,
	})
	if err != nil {
		t.Fatalf("picking head card failed: %v", err)
	}
	if gs.HeadOwner != 0 {
		t.Fatalf("HeadOwner after pickup = %d, want 0", gs.HeadOwner)
	}
	if len(gs.DiscardPile) != 0 {
		t.Fatalf("discard should be empty after head pickup, got %v", gs.DiscardPile)
	}
	// Score should credit +HeadCardBonus to the picker.
	gs.Players[0].Hand = nil // ignore hand penalty for the assert
	gs.RoundOver = true
	sb := ScoreRound(gs)
	if sb[0].HeadBonus != rs.HeadCardBonus {
		t.Fatalf("head bonus = %d, want %d", sb[0].HeadBonus, rs.HeadCardBonus)
	}
}

// siblingsOf returns the three other same-rank cards of a different suit
// from c (always exists for any input card).
func siblingsOf(c Card) []Card {
	out := make([]Card, 0, 3)
	for s := Clubs; s <= Spades; s++ {
		if s == c.Suit {
			continue
		}
		out = append(out, Card{Suit: s, Rank: c.Rank})
	}
	return out
}

func TestDrawDiscardEmptyRejected(t *testing.T) {
	e := Engine{}
	gs, _, _ := e.Start([]string{"A", "B"}, DefaultRuleSet(), 6)
	gs.FirstMove = false
	gs.DiscardPile = nil // Start seeds it with the head card; drain to test.
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
