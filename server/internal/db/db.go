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

// ---- coin shop ----

// CoinPackage is a purchasable bundle of in-game coins. The set is defined in
// the server so the client can never invent a package id.
type CoinPackage struct {
	ID       string `json:"id"`
	Title    string `json:"title"`
	Coins    int64  `json:"coins"`
	PriceTHB int    `json:"price_thb"`
	Badge    string `json:"badge,omitempty"` // e.g. "popular"
}

// CoinPackages is the canonical shop menu. Adjust freely — order is preserved.
var CoinPackages = []CoinPackage{
	{ID: "starter", Title: "Starter", Coins: 1_000, PriceTHB: 29},
	{ID: "player", Title: "Player", Coins: 5_000, PriceTHB: 99, Badge: "popular"},
	{ID: "vip", Title: "VIP", Coins: 12_000, PriceTHB: 199},
	{ID: "whale", Title: "Whale", Coins: 50_000, PriceTHB: 699, Badge: "best_value"},
}

// FindPackage returns the package matching id (and whether it exists).
func FindPackage(id string) (CoinPackage, bool) {
	for _, p := range CoinPackages {
		if p.ID == id {
			return p, true
		}
	}
	return CoinPackage{}, false
}

// PurchasePackage atomically records a successful (mock) purchase and credits
// the guest's wallet. Real payment integration will wrap this with a
// provider-side capture before the credit. Returns the new balance.
func (d *DB) PurchasePackage(ctx context.Context, guestID uuid.UUID, pkg CoinPackage) (int64, error) {
	tx, err := d.Pool.Begin(ctx)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback(ctx) //nolint:errcheck
	if _, err = tx.Exec(ctx,
		`INSERT INTO purchases (id, guest_id, package_id, coins, price_thb, status)
		 VALUES ($1, $2, $3, $4, $5, 'mock_success')`,
		uuid.New(), guestID, pkg.ID, pkg.Coins, pkg.PriceTHB); err != nil {
		return 0, err
	}
	var newBal int64
	if err = tx.QueryRow(ctx,
		`UPDATE guest_users SET coins = coins + $2 WHERE id = $1 RETURNING coins`,
		guestID, pkg.Coins).Scan(&newBal); err != nil {
		return 0, err
	}
	if err = tx.Commit(ctx); err != nil {
		return 0, err
	}
	return newBal, nil
}

// ---- rank ladder ----

// Rank is the player's title derived from cumulative match wins.
type Rank struct {
	Title     string `json:"title"`
	Level     int    `json:"level"`               // 0..N
	Wins      int    `json:"wins"`                // current wins
	NextTitle string `json:"next_title,omitempty"`
	NextWins  int    `json:"next_wins,omitempty"` // wins needed for next rank
}

// rankLadder is the ordered (ascending) ยศ ladder. The first entry must be
// the floor (wins ≥ 0).
var rankLadder = []struct {
	Wins  int
	Title string
}{
	{0, "มือใหม่"},
	{1, "มือสมัครเล่น"},
	{5, "มือกลาง"},
	{20, "มือเก๋า"},
	{50, "เซียนไพ่"},
	{150, "จอมยุทธ"},
}

// ComputeRank maps a win count to the highest ladder title earned plus the
// remaining wins to the next rung (0 when already at the top).
func ComputeRank(wins int) Rank {
	if wins < 0 {
		wins = 0
	}
	cur := rankLadder[0]
	level := 0
	for i, r := range rankLadder {
		if wins >= r.Wins {
			cur = r
			level = i
		}
	}
	out := Rank{Title: cur.Title, Level: level, Wins: wins}
	if level+1 < len(rankLadder) {
		next := rankLadder[level+1]
		out.NextTitle = next.Title
		out.NextWins = next.Wins
	}
	return out
}

// ---- coin/play history ----

// GuestStats are the lifetime aggregates feeding the rank.
type GuestStats struct {
	MatchesPlayed  int   `json:"matches_played"`
	MatchesWon     int   `json:"matches_won"`
	LifetimeProfit int64 `json:"lifetime_profit"`
}

// LoadStats reads the guest's lifetime stats from match_settlements.
func (d *DB) LoadStats(ctx context.Context, guestID uuid.UUID) (GuestStats, error) {
	var s GuestStats
	err := d.Pool.QueryRow(ctx, `
		SELECT
			COALESCE(COUNT(*), 0),
			COALESCE(SUM(CASE WHEN is_winner THEN 1 ELSE 0 END), 0),
			COALESCE(SUM(coin_delta), 0)
		FROM match_settlements WHERE guest_id = $1`, guestID,
	).Scan(&s.MatchesPlayed, &s.MatchesWon, &s.LifetimeProfit)
	return s, err
}

// SettlementRow is one player's outcome of a finished match.
type SettlementRow struct {
	GuestID      uuid.UUID
	CoinDelta    int
	BalanceAfter int64
	IsWinner     bool
}

// RecordSettlement persists one row per player for a finished match.
func (d *DB) RecordSettlement(ctx context.Context, matchID uuid.UUID, rows []SettlementRow) error {
	if len(rows) == 0 {
		return nil
	}
	tx, err := d.Pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx) //nolint:errcheck
	for _, r := range rows {
		if _, err = tx.Exec(ctx,
			`INSERT INTO match_settlements
			   (id, match_id, guest_id, coin_delta, balance_after, is_winner)
			 VALUES ($1,$2,$3,$4,$5,$6)`,
			uuid.New(), matchID, r.GuestID, r.CoinDelta, r.BalanceAfter, r.IsWinner,
		); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}

// CoinHistoryRow is one entry in the "my games" timeline.
type CoinHistoryRow struct {
	MatchID      uuid.UUID `json:"match_id"`
	RoomID       string    `json:"room_id"`
	Bet          int       `json:"bet"`
	CoinDelta    int       `json:"coin_delta"`
	BalanceAfter int64     `json:"balance_after"`
	IsWinner     bool      `json:"is_winner"`
	CreatedAt    time.Time `json:"created_at"`
}

// CoinHistory returns the guest's recent match outcomes, newest first.
func (d *DB) CoinHistory(ctx context.Context, guestID uuid.UUID, limit int) ([]CoinHistoryRow, error) {
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	rows, err := d.Pool.Query(ctx, `
		SELECT m.id, m.room_id, COALESCE(m.bet, 0),
		       s.coin_delta, s.balance_after, s.is_winner, s.created_at
		  FROM match_settlements s
		  JOIN matches m ON m.id = s.match_id
		 WHERE s.guest_id = $1
		 ORDER BY s.created_at DESC
		 LIMIT $2`, guestID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []CoinHistoryRow
	for rows.Next() {
		var r CoinHistoryRow
		if err := rows.Scan(&r.MatchID, &r.RoomID, &r.Bet,
			&r.CoinDelta, &r.BalanceAfter, &r.IsWinner, &r.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// RoomHistoryPlayer is one row inside a room-history match record.
type RoomHistoryPlayer struct {
	Name      string `json:"name"`
	CoinDelta int    `json:"coin_delta"`
	IsWinner  bool   `json:"is_winner"`
}

// RoomHistoryMatch groups all per-player settlements for one finished match.
type RoomHistoryMatch struct {
	MatchID   uuid.UUID           `json:"match_id"`
	Bet       int                 `json:"bet"`
	FinishedAt *time.Time         `json:"finished_at,omitempty"`
	Players   []RoomHistoryPlayer `json:"players"`
}

// RoomHistory returns recent finished matches in a room with each player's
// settlement; rows are aggregated client-side per match.
func (d *DB) RoomHistory(ctx context.Context, roomID string, limit int) ([]RoomHistoryMatch, error) {
	if limit <= 0 || limit > 50 {
		limit = 20
	}
	rows, err := d.Pool.Query(ctx, `
		SELECT m.id, COALESCE(m.bet, 0), m.finished_at,
		       g.display_name, s.coin_delta, s.is_winner
		  FROM matches m
		  JOIN match_settlements s ON s.match_id = m.id
		  JOIN guest_users g       ON g.id = s.guest_id
		 WHERE m.room_id = $1
		 ORDER BY m.created_at DESC, m.id, s.id
		 LIMIT $2`, roomID, limit*4)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	matches := make(map[uuid.UUID]*RoomHistoryMatch)
	order := []uuid.UUID{}
	for rows.Next() {
		var id uuid.UUID
		var bet int
		var finished *time.Time
		var p RoomHistoryPlayer
		if err := rows.Scan(&id, &bet, &finished, &p.Name, &p.CoinDelta, &p.IsWinner); err != nil {
			return nil, err
		}
		m, ok := matches[id]
		if !ok {
			m = &RoomHistoryMatch{MatchID: id, Bet: bet, FinishedAt: finished}
			matches[id] = m
			order = append(order, id)
		}
		m.Players = append(m.Players, p)
	}
	out := make([]RoomHistoryMatch, 0, len(order))
	for i, id := range order {
		if i >= limit {
			break
		}
		out = append(out, *matches[id])
	}
	return out, rows.Err()
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
