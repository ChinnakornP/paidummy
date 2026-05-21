package db

import (
	"context"

	"github.com/google/uuid"
)

// RegisterDeviceToken upserts a push token for a guest+platform. Re-sending
// the same token just bumps updated_at.
func (d *DB) RegisterDeviceToken(ctx context.Context, guestID uuid.UUID, token, platform string) error {
	if platform == "" {
		platform = "unknown"
	}
	_, err := d.Pool.Exec(ctx, `
		INSERT INTO device_tokens (guest_id, token, platform, updated_at)
		VALUES ($1, $2, $3, now())
		ON CONFLICT (guest_id, token)
		DO UPDATE SET platform = EXCLUDED.platform, updated_at = now()`,
		guestID, token, platform)
	return err
}

// DeviceTokens returns all push tokens registered for a guest (used by the
// Notifier when fanning out a push).
func (d *DB) DeviceTokens(ctx context.Context, guestID uuid.UUID) ([]string, error) {
	rows, err := d.Pool.Query(ctx,
		`SELECT token FROM device_tokens WHERE guest_id = $1`, guestID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var t string
		if err := rows.Scan(&t); err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}
