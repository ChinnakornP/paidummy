package game

// ActionType enumerates the moves a player may submit on their turn.
type ActionType uint8

const (
	ActDrawDeck    ActionType = iota // จั่ว: take top of draw pile
	ActDrawDiscard                   // เก็บ: take top of discard pile
	ActMeld                          // เกิด: lay a new set/run from hand
	ActLayOff                        // ฝาก: extend an existing table meld
	ActKnock                         // น็อค: go out
	ActDiscard                       // ทิ้ง: end turn by discarding one card
)

// Action is a pure, transport-free description of a player move. The WebSocket
// layer translates JSON into this; the engine never sees JSON.
type Action struct {
	Type   ActionType
	Cards  []Card    // ActMeld, ActLayOff
	MeldID string    // ActLayOff: target table meld
	End    LayOffEnd // ActLayOff
	Card   Card      // ActKnock (knock card), ActDiscard (discarded card)
	Dark   bool      // ActKnock: blind/หลับ knock (no prior meld this round)
}

// EventType enumerates domain events produced by ApplyAction. The room layer
// turns these into per-player WebSocket messages; the engine emits the full
// truth and the ws view layer filters what each player may see.
type EventType uint8

const (
	EvtDrewDeck EventType = iota
	EvtDrewDiscard
	EvtMelded
	EvtLaidOff
	EvtKnocked
	EvtDiscarded
	EvtTurnChanged
	EvtRoundOver
)

// Event is a single observable change resulting from an Action.
type Event struct {
	Type   EventType
	Player int    // actor (or new active player for EvtTurnChanged)
	Card   Card   // drawn/discarded/knock card where applicable
	Cards  []Card // melded/laid-off cards
	MeldID string // meld created or extended
	Reason string // EvtRoundOver: "knock" | "deck_exhaust"
}
