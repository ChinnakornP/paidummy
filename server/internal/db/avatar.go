package db

import (
	"context"
	"errors"

	"github.com/google/uuid"
)

// AllowedAvatars is the canonical preset palette. The client picker shows
// exactly these and the server rejects any avatar string that isn't in the
// set, so a misbehaving client can't paint custom emojis on the felt.
var AllowedAvatars = []string{
	"🙂", "😎", "🐱", "🐶", "🐰", "🐸",
	"🦊", "🐯", "🐼", "🐨", "🦄", "🦁",
}

// DefaultAvatar matches the column default in the 0006 migration.
const DefaultAvatar = "🙂"

// ErrInvalidAvatar is returned by SetAvatar when the requested glyph isn't
// in the preset palette.
var ErrInvalidAvatar = errors.New("avatar not in preset palette")

func isAllowedAvatar(a string) bool {
	for _, v := range AllowedAvatars {
		if v == a {
			return true
		}
	}
	return false
}

// Avatar reads the guest's currently selected avatar (returns DefaultAvatar
// if the row hasn't been backfilled for some reason).
func (d *DB) Avatar(ctx context.Context, id uuid.UUID) (string, error) {
	var a string
	if err := d.Pool.QueryRow(ctx,
		`SELECT avatar FROM guest_users WHERE id = $1`, id,
	).Scan(&a); err != nil {
		return "", err
	}
	if a == "" {
		return DefaultAvatar, nil
	}
	return a, nil
}

// SetAvatar updates the guest's avatar, rejecting any value not in
// AllowedAvatars.
func (d *DB) SetAvatar(ctx context.Context, id uuid.UUID, avatar string) error {
	if !isAllowedAvatar(avatar) {
		return ErrInvalidAvatar
	}
	_, err := d.Pool.Exec(ctx,
		`UPDATE guest_users SET avatar = $2 WHERE id = $1`, id, avatar)
	return err
}
