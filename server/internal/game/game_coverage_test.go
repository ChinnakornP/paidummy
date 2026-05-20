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

// TestDrawDiscardUsesAboveTargetCards: the user's "10A29 / hand 8" case —
// picking 10 deep in the pile combined with 9 (which sits above 10 in the
// pile) and 8 (from hand) forms a valid 10-9-8 run. The remaining above-
// target cards (A and 2) fall into the hand as extras.
func TestDrawDiscardUsesAboveTargetCards(t *testing.T) {
	e := Engine{}
	rs := DefaultRuleSet()
	gs, _, _ := e.Start([]string{"A", "B"}, rs, 21)

	gs.FirstMove = false
	gs.Turn = 0
	gs.Phase = PhaseDraw
	// Pile oldest→newest: TS (10♠), AD, 2C, 9S.
	gs.DiscardPile = cards("TS", "AD", "2C", "9S")
	gs.Players[0].Hand = cards("8S", "KH")

	_, err := e.ApplyAction(gs, 0, Action{
		Type:  ActDrawDiscard,
		Card:  MustCard("TS"),
		Cards: cards("9S", "8S"), // 9S from pile-above, 8S from hand
	})
	if err != nil {
		t.Fatalf("pickup with above-target card failed: %v", err)
	}
	if len(gs.Melds) != 1 || len(gs.Melds[0].Cards) != 3 {
		t.Fatalf("expected 8-9-10♠ meld, got %v", gs.Melds)
	}
	if gs.Melds[0].Kind != MeldRun {
		t.Fatalf("expected a run, got %v", gs.Melds[0].Kind)
	}
	// Pile drained: target + above all left it.
	if len(gs.DiscardPile) != 0 {
		t.Fatalf("discard should be empty, got %v", gs.DiscardPile)
	}
	// Hand: started [8S, KH], -8S used in meld, +AD+2C extras → [KH, AD, 2C].
	if len(gs.Players[0].Hand) != 3 {
		t.Fatalf("hand len = %d, want 3", len(gs.Players[0].Hand))
	}
	hand := map[Card]bool{}
	for _, c := range gs.Players[0].Hand {
		hand[c] = true
	}
	for _, want := range cards("KH", "AD", "2C") {
		if !hand[want] {
			t.Errorf("hand should contain %s, got %v", want, gs.Players[0].Hand)
		}
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

// TestDiscardFullPenalty: a player discards a card that could've been laid
// off onto a table meld. The discarder's DumpPenalty accumulator should
// bump by rs.DumpPenalty.
func TestDiscardFullPenalty(t *testing.T) {
	e := Engine{}
	rs := DefaultRuleSet()
	gs, _, _ := e.Start([]string{"A", "B"}, rs, 21)
	gs.FirstMove = false
	gs.Turn = 0
	gs.Phase = PhaseMeld
	m, _ := NewMeld(gs.nextMeldID(), cards("5D", "6D", "7D"), 1, rs)
	gs.Melds = []Meld{m}
	gs.Players[0].Hand = cards("4D", "9C")

	_, err := e.ApplyAction(gs, 0, Action{Type: ActDiscard, Card: MustCard("4D")})
	if err != nil {
		t.Fatalf("discard errored: %v", err)
	}
	if got := gs.DumpPenalties[0]; got != rs.DumpPenalty {
		t.Fatalf("DumpPenalties[0] = %d, want %d", got, rs.DumpPenalty)
	}
}

// TestDiscardDummyPenalty: player 0 discards 8S, then player 1 picks it up
// via draw_discard to form 6S-7S-8S. Player 0 (the original discarder) gets
// the ทิ้งดัมมี่ penalty.
func TestDiscardDummyPenalty(t *testing.T) {
	e := Engine{}
	rs := DefaultRuleSet()
	gs, _, _ := e.Start([]string{"A", "B"}, rs, 21)
	gs.FirstMove = false
	gs.Turn = 0
	gs.Phase = PhaseMeld
	gs.Players[0].Hand = cards("8S", "KH")
	gs.Players[1].Hand = cards("6S", "7S", "AC")

	if _, err := e.ApplyAction(gs, 0, Action{Type: ActDiscard, Card: MustCard("8S")}); err != nil {
		t.Fatalf("p0 discard: %v", err)
	}
	if gs.DumpPenalties[0] != 0 {
		t.Fatalf("p0 should not yet have full penalty, got %d", gs.DumpPenalties[0])
	}
	_, err := e.ApplyAction(gs, 1, Action{
		Type:  ActDrawDiscard,
		Card:  MustCard("8S"),
		Cards: cards("6S", "7S"),
	})
	if err != nil {
		t.Fatalf("p1 draw_discard: %v", err)
	}
	if gs.DumpPenalties[0] != rs.DumpPenalty {
		t.Fatalf("p0 should owe dummy penalty %d, got %d",
			rs.DumpPenalty, gs.DumpPenalties[0])
	}
	if gs.DumpPenalties[1] != 0 {
		t.Fatalf("p1 should owe nothing, got %d", gs.DumpPenalties[1])
	}
}

// TestDrawDiscardLayoff (ฝากดัมมี่): player picks up the discard top and
// lays it directly onto an existing meld instead of forming a new one. The
// original discarder owes the ทิ้งดัมมี่ penalty.
func TestDrawDiscardLayoff(t *testing.T) {
	e := Engine{}
	rs := DefaultRuleSet()
	gs, _, _ := e.Start([]string{"A", "B"}, rs, 21)
	gs.FirstMove = false

	// Setup: player 1 already has 5D-6D-7D on the table.
	m, _ := NewMeld(gs.nextMeldID(), cards("5D", "6D", "7D"), 1, rs)
	gs.Melds = []Meld{m}
	gs.Turn = 0
	gs.Phase = PhaseMeld
	gs.Players[0].Hand = cards("8D", "KH")
	if _, err := e.ApplyAction(gs, 0, Action{Type: ActDiscard, Card: MustCard("8D")}); err != nil {
		t.Fatalf("p0 discard: %v", err)
	}

	// Player 1's draw: ฝากดัมมี่ on 8D → meld m1.
	_, err := e.ApplyAction(gs, 1, Action{
		Type:   ActDrawDiscard,
		Card:   MustCard("8D"),
		MeldID: "m1",
	})
	if err != nil {
		t.Fatalf("ฝากดัมมี่ errored: %v", err)
	}
	if len(gs.Melds[0].Cards) != 4 {
		t.Fatalf("meld should be 4 cards (5D6D7D8D), got %v", gs.Melds[0].Cards)
	}
	// Pile started with the dealt head card + 8D after p0's discard; only
	// 8D should leave, head card stays.
	if len(gs.DiscardPile) != 1 {
		t.Fatalf("discard should hold only the head card, got %v", gs.DiscardPile)
	}
	// p0 owes ทิ้งเต็ม + ทิ้งดัมมี่ = 2 × DumpPenalty.
	if gs.DumpPenalties[0] != 2*rs.DumpPenalty {
		t.Fatalf("p0 penalty = %d, want %d", gs.DumpPenalties[0], 2*rs.DumpPenalty)
	}
	if gs.Phase != PhaseMeld {
		t.Fatalf("phase = %v, want PhaseMeld", gs.Phase)
	}
}
