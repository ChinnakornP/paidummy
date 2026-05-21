package db

import (
	"context"

	"github.com/google/uuid"
)

// ReplayScore is one player's score in one round.
type ReplayScore struct {
	Name  string `json:"name"`
	Score int    `json:"score"`
}

// ReplayRound is a single round of a match with its end reason and the
// per-player scores (highest first).
type ReplayRound struct {
	RoundNo int           `json:"round_no"`
	Reason  string        `json:"reason"`
	Scores  []ReplayScore `json:"scores"`
}

// MatchReplay returns the round-by-round score log for a match — a
// lightweight "replay" built from persisted round_scores (the full
// move-by-move stream would need event persistence; this is the score view).
func (d *DB) MatchReplay(ctx context.Context, matchID uuid.UUID) ([]ReplayRound, error) {
	rows, err := d.Pool.Query(ctx, `
		SELECT r.round_no, COALESCE(r.ended_reason,''), g.display_name, rs.score
		  FROM rounds r
		  JOIN round_scores rs ON rs.round_id = r.id
		  JOIN guest_users g   ON g.id = rs.guest_id
		 WHERE r.match_id = $1
		 ORDER BY r.round_no ASC, rs.score DESC`, matchID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []ReplayRound
	byRound := map[int]int{} // round_no → index in out
	for rows.Next() {
		var roundNo int
		var reason, name string
		var score int
		if err := rows.Scan(&roundNo, &reason, &name, &score); err != nil {
			return nil, err
		}
		idx, ok := byRound[roundNo]
		if !ok {
			idx = len(out)
			byRound[roundNo] = idx
			out = append(out, ReplayRound{RoundNo: roundNo, Reason: reason})
		}
		out[idx].Scores = append(out[idx].Scores, ReplayScore{Name: name, Score: score})
	}
	return out, rows.Err()
}
