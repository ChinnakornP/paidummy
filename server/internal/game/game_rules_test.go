package game

import "testing"

func cards(ss ...string) []Card {
	out := make([]Card, len(ss))
	for i, s := range ss {
		out[i] = MustCard(s)
	}
	return out
}

func TestNewDeckIs52Unique(t *testing.T) {
	d := NewDeck()
	if len(d) != 52 {
		t.Fatalf("deck len = %d, want 52", len(d))
	}
	seen := map[Card]bool{}
	for _, c := range d {
		if seen[c] {
			t.Fatalf("duplicate card %s", c)
		}
		seen[c] = true
	}
}

func TestShuffleDeterministic(t *testing.T) {
	a := Shuffle(NewDeck(), 42)
	b := Shuffle(NewDeck(), 42)
	c := Shuffle(NewDeck(), 43)
	for i := range a {
		if a[i] != b[i] {
			t.Fatalf("same seed differs at %d", i)
		}
	}
	same := true
	for i := range a {
		if a[i] != c[i] {
			same = false
			break
		}
	}
	if same {
		t.Fatal("different seeds produced identical order")
	}
}

func TestDealSizes(t *testing.T) {
	rs := DefaultRuleSet()
	for _, tc := range []struct{ n, hand, draw int }{
		{2, 11, 52 - 22 - 1},
		{3, 9, 52 - 27 - 1},
		{4, 7, 52 - 28 - 1},
	} {
		hands, _, draw := Deal(Shuffle(NewDeck(), 1), tc.n, rs)
		if len(hands) != tc.n {
			t.Fatalf("n=%d hands=%d", tc.n, len(hands))
		}
		for _, h := range hands {
			if len(h) != tc.hand {
				t.Fatalf("n=%d hand size=%d want %d", tc.n, len(h), tc.hand)
			}
		}
		if len(draw) != tc.draw {
			t.Fatalf("n=%d draw=%d want %d", tc.n, len(draw), tc.draw)
		}
	}
}

func TestMeldClassification(t *testing.T) {
	rs := DefaultRuleSet()
	cases := []struct {
		name string
		in   []Card
		kind MeldKind
		ok   bool
	}{
		{"set3", cards("7C", "7D", "7H"), MeldSet, true},
		{"set4", cards("7C", "7D", "7H", "7S"), MeldSet, true},
		{"run3", cards("5S", "6S", "7S"), MeldRun, true},
		{"too short", cards("7C", "7D"), 0, false},
		{"mixed suit run", cards("5S", "6H", "7S"), 0, false},
		{"non consecutive", cards("5S", "7S", "9S"), 0, false},
	}
	for _, c := range cases {
		k, _, err := classifyMeld(c.in, rs)
		if c.ok && err != nil {
			t.Errorf("%s: unexpected err %v", c.name, err)
		}
		if !c.ok && err == nil {
			t.Errorf("%s: expected error, got kind %v", c.name, k)
		}
		if c.ok && k != c.kind {
			t.Errorf("%s: kind=%v want %v", c.name, k, c.kind)
		}
	}
}

func TestAceRunsAndNoWrap(t *testing.T) {
	rs := DefaultRuleSet()
	if _, ah, err := classifyMeld(cards("AS", "2S", "3S"), rs); err != nil || ah {
		t.Errorf("A-2-3 should be valid ace-low, got ah=%v err=%v", ah, err)
	}
	if _, ah, err := classifyMeld(cards("QS", "KS", "AS"), rs); err != nil || !ah {
		t.Errorf("Q-K-A should be valid ace-high, got ah=%v err=%v", ah, err)
	}
	if _, _, err := classifyMeld(cards("KS", "AS", "2S"), rs); err == nil {
		t.Error("K-A-2 must be rejected (no wrap)")
	}
}

func TestAcePoints(t *testing.T) {
	rs := DefaultRuleSet()
	low := MustCard("AH")
	if low.Points(rs, false) != 1 {
		t.Errorf("ace low = %d want 1", low.Points(rs, false))
	}
	if low.Points(rs, true) != 10 {
		t.Errorf("ace high = %d want 10", low.Points(rs, true))
	}
}

func TestLayOff(t *testing.T) {
	rs := DefaultRuleSet()
	run, _ := NewMeld("m1", cards("5S", "6S", "7S"), 0, rs)
	if m, err := canLayOff(run, cards("8S"), rs); err != nil || len(m.Cards) != 4 {
		t.Errorf("tail layoff 8S failed: %v", err)
	}
	if m, err := canLayOff(run, cards("4S"), rs); err != nil || m.Cards[0] != MustCard("4S") {
		t.Errorf("head layoff 4S failed: %v", err)
	}
	if _, err := canLayOff(run, cards("8H"), rs); err == nil {
		t.Error("wrong-suit layoff must fail")
	}
	set, _ := NewMeld("m2", cards("7C", "7D", "7H"), 0, rs)
	if m, err := canLayOff(set, cards("7S"), rs); err != nil || len(m.Cards) != 4 {
		t.Errorf("set layoff 7S failed: %v", err)
	}
	if _, err := canLayOff(set, cards("8S"), rs); err == nil {
		t.Error("wrong-rank set layoff must fail")
	}
	aceHigh, _ := NewMeld("m3", cards("QS", "KS", "AS"), 0, rs)
	if _, err := canLayOff(aceHigh, cards("2S"), rs); err == nil {
		t.Error("Q-K-A + 2S must fail (no wrap)")
	}
}

func TestScoringValues(t *testing.T) {
	rs := DefaultRuleSet()
	set, _ := NewMeld("m1", cards("7C", "7D", "7H"), 0, rs)
	if got := meldPoints(set, rs); got != 21 {
		t.Errorf("7-set = %d want 21", got)
	}
	speto2, _ := NewMeld("m2", cards("2C", "2D", "2H"), 0, rs) // 2C=50
	if got := meldPoints(speto2, rs); got != 54 {
		t.Errorf("2-set with 2C speto = %d want 54", got)
	}
	speto3, _ := NewMeld("m3", cards("QC", "QD", "QS"), 0, rs) // QS=50
	if got := meldPoints(speto3, rs); got != 70 {
		t.Errorf("Q-set with QS speto = %d want 70", got)
	}
	faceRun, _ := NewMeld("m4", cards("TS", "JS", "QS", "KS"), 0, rs) // QS speto here too
	if got := meldPoints(faceRun, rs); got != 80 {
		t.Errorf("T-J-Q-K spades (QS speto) = %d want 80", got)
	}
}

// buildScoringState makes a finished round for scoring assertions.
func buildScoringState(rs RuleSet) *GameState {
	return &GameState{
		Players: []Player{{ID: "A"}, {ID: "B"}},
		RuleSet: rs, HeadOwner: -1, Knocker: -1, RoundOver: true,
	}
}

func TestKnockVariants(t *testing.T) {
	rs := DefaultRuleSet()
	mk := func(dark, suit bool) ScoreBreakdown {
		gs := buildScoringState(rs)
		gs.Knocker = 0
		gs.KnockDark = dark
		gs.KnockSuit = suit
		return ScoreRound(gs)[0]
	}
	std := mk(false, false)
	if std.KnockBonus != 50 || std.KnockCardBonus != 50 {
		t.Errorf("standard knock = %+v want bonus 50/50", std)
	}
	if d := mk(true, false); d.KnockBonus != 100 {
		t.Errorf("dark knock bonus = %d want 100", d.KnockBonus)
	}
	if s := mk(false, true); s.KnockBonus != 100 {
		t.Errorf("suit knock bonus = %d want 100", s.KnockBonus)
	}
	if ds := mk(true, true); ds.KnockBonus != 200 {
		t.Errorf("dark+suit knock bonus = %d want 200", ds.KnockBonus)
	}
}

func TestScoringHeadAndHandPenalty(t *testing.T) {
	rs := DefaultRuleSet()
	gs := buildScoringState(rs)
	gs.HeadOwner = 1
	gs.Players[0].Hand = cards("KD", "5C") // 10 + 5 left in hand
	sb := ScoreRound(gs)
	if sb[1].HeadBonus != 50 {
		t.Errorf("head bonus = %d want 50", sb[1].HeadBonus)
	}
	if sb[0].HandPenalty != -15 {
		t.Errorf("hand penalty = %d want -15", sb[0].HandPenalty)
	}
	if sb[0].Total != -15 {
		t.Errorf("total = %d want -15", sb[0].Total)
	}
}
