// Package db is the Postgres durable store: connection pool, an embedded
// forward-only migration runner, and typed query helpers.
package db

import (
	"context"
	"embed"
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

//go:embed migrations/*.up.sql
var migrationFS embed.FS

// DB wraps a pgx pool.
type DB struct{ Pool *pgxpool.Pool }

// Connect opens a pooled connection and verifies it.
func Connect(ctx context.Context, dsn string) (*DB, error) {
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		return nil, fmt.Errorf("pgx pool: %w", err)
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("pg ping: %w", err)
	}
	return &DB{Pool: pool}, nil
}

func (d *DB) Close() { d.Pool.Close() }

// Migrate applies every embedded *.up.sql once, in filename order, tracked in
// schema_migrations. It is idempotent and safe to run on every boot.
func (d *DB) Migrate(ctx context.Context) error {
	if _, err := d.Pool.Exec(ctx,
		`CREATE TABLE IF NOT EXISTS schema_migrations (version TEXT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now())`,
	); err != nil {
		return err
	}
	entries, err := migrationFS.ReadDir("migrations")
	if err != nil {
		return err
	}
	names := make([]string, 0, len(entries))
	for _, e := range entries {
		if strings.HasSuffix(e.Name(), ".up.sql") {
			names = append(names, e.Name())
		}
	}
	sort.Strings(names)
	for _, name := range names {
		var exists bool
		if err := d.Pool.QueryRow(ctx,
			`SELECT EXISTS(SELECT 1 FROM schema_migrations WHERE version=$1)`, name,
		).Scan(&exists); err != nil {
			return err
		}
		if exists {
			continue
		}
		sqlBytes, err := migrationFS.ReadFile("migrations/" + name)
		if err != nil {
			return err
		}
		if _, err := d.Pool.Exec(ctx, string(sqlBytes)); err != nil {
			return fmt.Errorf("apply %s: %w", name, err)
		}
		if _, err := d.Pool.Exec(ctx,
			`INSERT INTO schema_migrations (version) VALUES ($1)`, name,
		); err != nil {
			return err
		}
	}
	return nil
}

// ---- guest users & sessions ----

// StartingCoins is the wallet balance every new guest is seeded with
// (matches the guest_users.coins column default).
const StartingCoins int64 = 1000

// GuestUser is a passwordless player identity with a coin wallet.
type GuestUser struct {
	ID          uuid.UUID
	DisplayName string
	CreatedAt   time.Time
	Coins       int64
}

// CreateGuest inserts a new guest user (coins default to StartingCoins).
func (d *DB) CreateGuest(ctx context.Context, name string) (GuestUser, error) {
	g := GuestUser{
		ID: uuid.New(), DisplayName: name,
		CreatedAt: time.Now(), Coins: StartingCoins,
	}
	_, err := d.Pool.Exec(ctx,
		`INSERT INTO guest_users (id, display_name) VALUES ($1, $2)`, g.ID, g.DisplayName)
	return g, err
}

// Coins returns a guest's current wallet balance.
func (d *DB) Coins(ctx context.Context, id uuid.UUID) (int64, error) {
	var c int64
	err := d.Pool.QueryRow(ctx,
		`SELECT coins FROM guest_users WHERE id = $1`, id).Scan(&c)
	return c, err
}

// SettleMatch moves coins at match end: each loser pays up to perLoser (never
// more than they hold), the winner collects the whole pot. It is atomic and
// returns the signed delta and new balance per guest.
func (d *DB) SettleMatch(ctx context.Context, winner uuid.UUID, perLoser int64, losers []uuid.UUID) (deltas, balances map[uuid.UUID]int64, err error) {
	deltas = map[uuid.UUID]int64{}
	balances = map[uuid.UUID]int64{}
	tx, err := d.Pool.Begin(ctx)
	if err != nil {
		return nil, nil, err
	}
	defer tx.Rollback(ctx) //nolint:errcheck

	var pot int64
	for _, l := range losers {
		var cur int64
		if err = tx.QueryRow(ctx,
			`SELECT coins FROM guest_users WHERE id = $1 FOR UPDATE`,
			l).Scan(&cur); err != nil {
			return nil, nil, err
		}
		paid := perLoser
		if paid > cur {
			paid = cur
		}
		if paid < 0 {
			paid = 0
		}
		var bal int64
		if err = tx.QueryRow(ctx,
			`UPDATE guest_users SET coins = coins - $2 WHERE id = $1 RETURNING coins`,
			l, paid).Scan(&bal); err != nil {
			return nil, nil, err
		}
		pot += paid
		deltas[l] = -paid
		balances[l] = bal
	}
	var wbal int64
	if err = tx.QueryRow(ctx,
		`UPDATE guest_users SET coins = coins + $2 WHERE id = $1 RETURNING coins`,
		winner, pot).Scan(&wbal); err != nil {
		return nil, nil, err
	}
	deltas[winner] = pot
	balances[winner] = wbal
	if err = tx.Commit(ctx); err != nil {
		return nil, nil, err
	}
	return deltas, balances, nil
}

// CreateSession stores a session token for a guest.
func (d *DB) CreateSession(ctx context.Context, token string, guestID uuid.UUID, expires time.Time) error {
	_, err := d.Pool.Exec(ctx,
		`INSERT INTO sessions (token, guest_id, expires_at) VALUES ($1, $2, $3)`,
		token, guestID, expires)
	return err
}

// LookupSession resolves a non-expired session token to its guest.
func (d *DB) LookupSession(ctx context.Context, token string) (GuestUser, bool, error) {
	var g GuestUser
	err := d.Pool.QueryRow(ctx,
		`SELECT g.id, g.display_name, g.created_at, g.coins
		   FROM sessions s JOIN guest_users g ON g.id = s.guest_id
		  WHERE s.token = $1 AND s.expires_at > now()`, token,
	).Scan(&g.ID, &g.DisplayName, &g.CreatedAt, &g.Coins)
	if err != nil {
		if strings.Contains(err.Error(), "no rows") {
			return GuestUser{}, false, nil
		}
		return GuestUser{}, false, err
	}
	return g, true, nil
}

// ---- match / round persistence (used by the room layer) ----

// CreateMatch records a match with its seated players.
func (d *DB) CreateMatch(ctx context.Context, id uuid.UUID, roomID string, target, bet int, rulesetJSON []byte, players []uuid.UUID) error {
	tx, err := d.Pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx) //nolint:errcheck
	if _, err = tx.Exec(ctx,
		`INSERT INTO matches (id, room_id, status, target_score, bet, ruleset) VALUES ($1,$2,'active',$3,$4,$5)`,
		id, roomID, target, bet, rulesetJSON); err != nil {
		return err
	}
	for seat, gid := range players {
		if _, err = tx.Exec(ctx,
			`INSERT INTO match_players (match_id, guest_id, seat) VALUES ($1,$2,$3)`,
			id, gid, seat); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}

// RoundScore is one player's persisted result for a round.
type RoundScore struct {
	GuestID   uuid.UUID
	Score     int
	Breakdown []byte // JSON
}

// SaveRound persists a finished round and its per-player scores atomically.
func (d *DB) SaveRound(ctx context.Context, matchID uuid.UUID, roundNo int, seed int64, reason string, knocker *uuid.UUID, scores []RoundScore) error {
	tx, err := d.Pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx) //nolint:errcheck
	roundID := uuid.New()
	if _, err = tx.Exec(ctx,
		`INSERT INTO rounds (id, match_id, round_no, seed, ended_reason, knocker_guest_id)
		 VALUES ($1,$2,$3,$4,$5,$6)`,
		roundID, matchID, roundNo, seed, reason, knocker); err != nil {
		return err
	}
	for _, s := range scores {
		if _, err = tx.Exec(ctx,
			`INSERT INTO round_scores (round_id, guest_id, score, breakdown) VALUES ($1,$2,$3,$4)`,
			roundID, s.GuestID, s.Score, s.Breakdown); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}

// FinishMatch marks a match finished with its winner.
func (d *DB) FinishMatch(ctx context.Context, matchID uuid.UUID, winner uuid.UUID) error {
	_, err := d.Pool.Exec(ctx,
		`UPDATE matches SET status='finished', finished_at=now(), winner_guest_id=$2 WHERE id=$1`,
		matchID, winner)
	return err
}

// MatchHistoryRow is a flattened match-history record for a guest.
type MatchHistoryRow struct {
	MatchID    uuid.UUID
	RoomID     string
	Status     string
	CreatedAt  time.Time
	TotalScore int
}

// MatchHistory returns matches a guest played, newest first.
func (d *DB) MatchHistory(ctx context.Context, guestID uuid.UUID, limit int) ([]MatchHistoryRow, error) {
	rows, err := d.Pool.Query(ctx, `
		SELECT m.id, m.room_id, m.status, m.created_at,
		       COALESCE(SUM(rs.score),0)
		  FROM matches m
		  JOIN match_players mp ON mp.match_id = m.id AND mp.guest_id = $1
		  LEFT JOIN rounds r ON r.match_id = m.id
		  LEFT JOIN round_scores rs ON rs.round_id = r.id AND rs.guest_id = $1
		 GROUP BY m.id
		 ORDER BY m.created_at DESC
		 LIMIT $2`, guestID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []MatchHistoryRow
	for rows.Next() {
		var r MatchHistoryRow
		if err := rows.Scan(&r.MatchID, &r.RoomID, &r.Status, &r.CreatedAt, &r.TotalScore); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}
