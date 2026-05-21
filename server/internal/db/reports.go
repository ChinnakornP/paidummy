package db

import (
	"context"
	"strings"
	"time"

	"github.com/google/uuid"
)

// CreateReport records one player reporting another. reason is trimmed and
// capped; empty reasons are stored as "unspecified".
func (d *DB) CreateReport(ctx context.Context, reporter, target uuid.UUID, reason string) error {
	reason = strings.TrimSpace(reason)
	if reason == "" {
		reason = "unspecified"
	}
	if len(reason) > 280 {
		reason = reason[:280]
	}
	_, err := d.Pool.Exec(ctx,
		`INSERT INTO reports (id, reporter_id, target_id, reason)
		 VALUES ($1, $2, $3, $4)`,
		uuid.New(), reporter, target, reason)
	return err
}

// SetBanned flips a guest's ban flag (admin action).
func (d *DB) SetBanned(ctx context.Context, target uuid.UUID, banned bool) error {
	_, err := d.Pool.Exec(ctx,
		`UPDATE guest_users SET banned = $2 WHERE id = $1`, target, banned)
	return err
}

// IsBanned reports whether the guest is banned. Best-effort: a lookup error
// is treated as not-banned so a transient DB blip can't lock everyone out.
func (d *DB) IsBanned(ctx context.Context, id uuid.UUID) bool {
	var banned bool
	if err := d.Pool.QueryRow(ctx,
		`SELECT banned FROM guest_users WHERE id = $1`, id,
	).Scan(&banned); err != nil {
		return false
	}
	return banned
}

// ReportRow is one report joined with reporter/target display names for the
// admin view.
type ReportRow struct {
	ID        uuid.UUID `json:"id"`
	Reporter  string    `json:"reporter"`
	Target    string    `json:"target"`
	TargetID  uuid.UUID `json:"target_id"`
	Reason    string    `json:"reason"`
	CreatedAt time.Time `json:"created_at"`
}

// RecentReports returns the newest reports for the admin dashboard.
func (d *DB) RecentReports(ctx context.Context, limit int) ([]ReportRow, error) {
	if limit <= 0 || limit > 200 {
		limit = 100
	}
	rows, err := d.Pool.Query(ctx, `
		SELECT r.id, rep.display_name, tgt.display_name, r.target_id,
		       r.reason, r.created_at
		  FROM reports r
		  JOIN guest_users rep ON rep.id = r.reporter_id
		  JOIN guest_users tgt ON tgt.id = r.target_id
		 ORDER BY r.created_at DESC
		 LIMIT $1`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []ReportRow
	for rows.Next() {
		var r ReportRow
		if err := rows.Scan(&r.ID, &r.Reporter, &r.Target, &r.TargetID,
			&r.Reason, &r.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}
