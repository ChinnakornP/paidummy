package db

import (
	"context"
	"time"

	"github.com/google/uuid"
)

// CollusionThreshold is how many times a winner must beat the same loser
// (in shared finished matches) before the pair is flagged. Tunable.
const CollusionThreshold = 5

// ScanCollusion runs the heuristic and records any newly-suspicious pairs.
// Heuristic v1: a (winner, loser) pair that co-occurred in ≥ threshold
// matches where the winner always won. Re-running replaces the flag set so
// counts stay current. Returns how many pairs were flagged.
func (d *DB) ScanCollusion(ctx context.Context) (int, error) {
	tx, err := d.Pool.Begin(ctx)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback(ctx) //nolint:errcheck

	// Rebuild the flag set from scratch each scan.
	if _, err = tx.Exec(ctx, `DELETE FROM collusion_flags`); err != nil {
		return 0, err
	}
	rows, err := tx.Query(ctx, `
		SELECT w.guest_id, l.guest_id, COUNT(*) AS n
		  FROM match_settlements w
		  JOIN match_settlements l
		    ON l.match_id = w.match_id AND l.guest_id <> w.guest_id
		 WHERE w.is_winner AND NOT l.is_winner
		 GROUP BY w.guest_id, l.guest_id
		HAVING COUNT(*) >= $1`, CollusionThreshold)
	if err != nil {
		return 0, err
	}
	type pair struct {
		w, l uuid.UUID
		n    int
	}
	var pairs []pair
	for rows.Next() {
		var p pair
		if err := rows.Scan(&p.w, &p.l, &p.n); err != nil {
			rows.Close()
			return 0, err
		}
		pairs = append(pairs, p)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return 0, err
	}
	for _, p := range pairs {
		if _, err = tx.Exec(ctx,
			`INSERT INTO collusion_flags (id, winner_id, loser_id, matches)
			 VALUES ($1,$2,$3,$4)`,
			uuid.New(), p.w, p.l, p.n); err != nil {
			return 0, err
		}
	}
	if err = tx.Commit(ctx); err != nil {
		return 0, err
	}
	return len(pairs), nil
}

// CollusionFlagRow is one flagged pair with display names for the admin view.
type CollusionFlagRow struct {
	Winner    string    `json:"winner"`
	Loser     string    `json:"loser"`
	Matches   int       `json:"matches"`
	CreatedAt time.Time `json:"created_at"`
}

// CollusionFlags returns the current flag set, most-suspicious first.
func (d *DB) CollusionFlags(ctx context.Context, limit int) ([]CollusionFlagRow, error) {
	if limit <= 0 || limit > 200 {
		limit = 100
	}
	rows, err := d.Pool.Query(ctx, `
		SELECT w.display_name, l.display_name, f.matches, f.created_at
		  FROM collusion_flags f
		  JOIN guest_users w ON w.id = f.winner_id
		  JOIN guest_users l ON l.id = f.loser_id
		 ORDER BY f.matches DESC
		 LIMIT $1`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []CollusionFlagRow
	for rows.Next() {
		var r CollusionFlagRow
		if err := rows.Scan(&r.Winner, &r.Loser, &r.Matches, &r.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}
