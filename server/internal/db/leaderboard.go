package db

import (
	"context"
	"fmt"

	"github.com/google/uuid"
)

// LeaderboardRow is one entry on the leaderboard, ranked highest profit
// first. `Wins` counts matches in the same window.
type LeaderboardRow struct {
	GuestID uuid.UUID `json:"guest_id"`
	Name    string    `json:"name"`
	Wins    int       `json:"wins"`
	Profit  int64     `json:"profit"`
}

// LeaderboardPeriod is the time window aggregated into the leaderboard.
type LeaderboardPeriod string

const (
	LeaderboardAllTime LeaderboardPeriod = "alltime"
	LeaderboardWeekly  LeaderboardPeriod = "weekly"
	LeaderboardDaily   LeaderboardPeriod = "daily"
)

// Leaderboard returns the top [limit] players by coin profit within the
// requested period. Players with zero settlements are omitted.
func (d *DB) Leaderboard(ctx context.Context, period LeaderboardPeriod, limit int) ([]LeaderboardRow, error) {
	if limit <= 0 || limit > 100 {
		limit = 20
	}
	where := ""
	switch period {
	case LeaderboardDaily:
		where = "WHERE s.created_at >= now() - interval '1 day'"
	case LeaderboardWeekly:
		where = "WHERE s.created_at >= now() - interval '7 days'"
	}
	q := fmt.Sprintf(`
		SELECT g.id, g.display_name,
		       COALESCE(SUM(CASE WHEN s.is_winner THEN 1 ELSE 0 END), 0)::int,
		       COALESCE(SUM(s.coin_delta), 0)::bigint
		  FROM match_settlements s
		  JOIN guest_users g ON g.id = s.guest_id
		 %s
		 GROUP BY g.id, g.display_name
		HAVING COUNT(*) > 0
		 ORDER BY COALESCE(SUM(s.coin_delta), 0) DESC, COUNT(*) DESC
		 LIMIT $1`, where)
	rows, err := d.Pool.Query(ctx, q, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]LeaderboardRow, 0, limit)
	for rows.Next() {
		var r LeaderboardRow
		if err := rows.Scan(&r.GuestID, &r.Name, &r.Wins, &r.Profit); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}
