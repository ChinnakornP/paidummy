package db

import (
	"context"
	"errors"

	"github.com/google/uuid"
)

// AllowedThemes is the cosmetic felt-theme palette set. The client maps each
// id to concrete colours; the server only validates the id so a client can't
// persist an unknown theme.
var AllowedThemes = []string{"classic", "midnight", "emerald", "ruby", "sand"}

// DefaultTheme matches the 0013 column default.
const DefaultTheme = "classic"

// ErrInvalidTheme is returned by SetTheme for an unknown theme id.
var ErrInvalidTheme = errors.New("theme not in allowed set")

func isAllowedTheme(t string) bool {
	for _, v := range AllowedThemes {
		if v == t {
			return true
		}
	}
	return false
}

// Theme reads the guest's selected theme (DefaultTheme fallback).
func (d *DB) Theme(ctx context.Context, id uuid.UUID) (string, error) {
	var t string
	if err := d.Pool.QueryRow(ctx,
		`SELECT theme FROM guest_users WHERE id = $1`, id,
	).Scan(&t); err != nil {
		return "", err
	}
	if t == "" {
		return DefaultTheme, nil
	}
	return t, nil
}

// SetTheme updates the guest's theme, rejecting unknown ids.
func (d *DB) SetTheme(ctx context.Context, id uuid.UUID, theme string) error {
	if !isAllowedTheme(theme) {
		return ErrInvalidTheme
	}
	_, err := d.Pool.Exec(ctx,
		`UPDATE guest_users SET theme = $2 WHERE id = $1`, id, theme)
	return err
}
