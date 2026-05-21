package db

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
)

// AdReward + AdCooldown define the mock rewarded-ad economy. Real ad SDK
// integration would replace the "always grants" body of ClaimAd with a
// server-side ad-completion verification before the credit.
const (
	AdReward   int64 = 200
	AdCooldown       = 30 * time.Minute
)

// ErrAdCooldown is returned by ClaimAd when the cooldown hasn't elapsed.
var ErrAdCooldown = errors.New("ad reward on cooldown")

// AdStatusInfo is the wire shape for the ad button state.
type AdStatusInfo struct {
	Available bool       `json:"available"`
	Reward    int64      `json:"reward"`
	NextClaim *time.Time `json:"next_claim,omitempty"`
}

// AdStatus reports whether the guest can claim a rewarded-ad bonus now.
func (d *DB) AdStatus(ctx context.Context, id uuid.UUID) (AdStatusInfo, error) {
	var last *time.Time
	if err := d.Pool.QueryRow(ctx,
		`SELECT last_ad_at FROM guest_users WHERE id = $1`, id,
	).Scan(&last); err != nil {
		return AdStatusInfo{}, err
	}
	out := AdStatusInfo{Reward: AdReward, Available: true}
	if last != nil {
		if next := last.Add(AdCooldown); time.Now().Before(next) {
			out.Available = false
			out.NextClaim = &next
		}
	}
	return out, nil
}

// ClaimAd credits the (mock) rewarded-ad bonus if the cooldown has elapsed.
// Returns the coins added and new balance.
func (d *DB) ClaimAd(ctx context.Context, id uuid.UUID) (coinsAdded int64, newBalance int64, err error) {
	tx, err := d.Pool.Begin(ctx)
	if err != nil {
		return 0, 0, err
	}
	defer tx.Rollback(ctx) //nolint:errcheck

	var last *time.Time
	if err = tx.QueryRow(ctx,
		`SELECT last_ad_at FROM guest_users WHERE id = $1 FOR UPDATE`, id,
	).Scan(&last); err != nil {
		return 0, 0, err
	}
	now := time.Now()
	if last != nil && now.Before(last.Add(AdCooldown)) {
		return 0, 0, ErrAdCooldown
	}
	if err = tx.QueryRow(ctx,
		`UPDATE guest_users SET coins = coins + $2, last_ad_at = $3
		 WHERE id = $1 RETURNING coins`,
		id, AdReward, now).Scan(&newBalance); err != nil {
		return 0, 0, err
	}
	if err = tx.Commit(ctx); err != nil {
		return 0, 0, err
	}
	return AdReward, newBalance, nil
}
