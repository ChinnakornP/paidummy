package db

import (
	"context"
	"strings"

	"github.com/google/uuid"
)

// ReferralBonus is the coin reward credited to both the referrer and the
// new player when the referred guest finishes their first match.
const ReferralBonus int64 = 500

// refCodeFor derives the shareable handle from the guest's UUID — first 8
// hex chars after stripping dashes. Deterministic so the migration backfill
// and runtime CreateGuest path agree.
func refCodeFor(id uuid.UUID) string {
	return strings.ReplaceAll(id.String(), "-", "")[:8]
}

// EnsureRefCode populates ref_code from the guest's UUID if it's still NULL
// (handles the small race where a row was inserted by an older binary that
// didn't backfill via the migration). Safe to call after CreateGuest.
func (d *DB) EnsureRefCode(ctx context.Context, id uuid.UUID) (string, error) {
	code := refCodeFor(id)
	_, err := d.Pool.Exec(ctx,
		`UPDATE guest_users SET ref_code = $2 WHERE id = $1 AND ref_code IS NULL`,
		id, code)
	if err != nil {
		return "", err
	}
	return code, nil
}

// RefCode returns the guest's shareable code. Returns the deterministic
// fallback if the column is still NULL for some reason.
func (d *DB) RefCode(ctx context.Context, id uuid.UUID) (string, error) {
	var code *string
	if err := d.Pool.QueryRow(ctx,
		`SELECT ref_code FROM guest_users WHERE id = $1`, id,
	).Scan(&code); err != nil {
		return "", err
	}
	if code == nil || *code == "" {
		return refCodeFor(id), nil
	}
	return *code, nil
}

// SetReferrer records `refCode` as the referrer of `guestID`. Idempotent —
// a guest can only have one referrer set; subsequent calls are no-ops.
// Returns the referrer's id (zero if no match) and whether anything changed.
func (d *DB) SetReferrer(ctx context.Context, guestID uuid.UUID, refCode string) (uuid.UUID, bool, error) {
	refCode = strings.TrimSpace(refCode)
	if refCode == "" {
		return uuid.Nil, false, nil
	}
	var refID uuid.UUID
	err := d.Pool.QueryRow(ctx,
		`SELECT id FROM guest_users WHERE ref_code = $1`, refCode,
	).Scan(&refID)
	if err != nil {
		// no rows → don't treat as an error; the player just typed a bad code.
		return uuid.Nil, false, nil
	}
	if refID == guestID {
		// You can't refer yourself.
		return uuid.Nil, false, nil
	}
	tag, err := d.Pool.Exec(ctx,
		`UPDATE guest_users SET referrer_id = $2 WHERE id = $1 AND referrer_id IS NULL`,
		guestID, refID)
	if err != nil {
		return uuid.Nil, false, err
	}
	return refID, tag.RowsAffected() == 1, nil
}

// MaybeAwardReferral fires the one-shot referral bonus if this is the
// guest's first finished match. Returns whether anything was credited and
// the referrer's id (or zero) so callers can broadcast the news.
//
// Atomicity: a single transaction reads/sets referral_rewarded and updates
// both wallets, so concurrent finishRound calls can't double-credit.
func (d *DB) MaybeAwardReferral(ctx context.Context, guestID uuid.UUID) (awarded bool, referrerID uuid.UUID, err error) {
	tx, err := d.Pool.Begin(ctx)
	if err != nil {
		return false, uuid.Nil, err
	}
	defer tx.Rollback(ctx) //nolint:errcheck

	var refID *uuid.UUID
	var rewarded bool
	if err = tx.QueryRow(ctx,
		`SELECT referrer_id, referral_rewarded FROM guest_users WHERE id = $1 FOR UPDATE`,
		guestID,
	).Scan(&refID, &rewarded); err != nil {
		return false, uuid.Nil, err
	}
	if rewarded || refID == nil {
		return false, uuid.Nil, nil
	}
	// First match completed?
	var matches int
	if err = tx.QueryRow(ctx,
		`SELECT COUNT(*) FROM match_settlements WHERE guest_id = $1`, guestID,
	).Scan(&matches); err != nil {
		return false, uuid.Nil, err
	}
	if matches < 1 {
		return false, uuid.Nil, nil
	}
	if _, err = tx.Exec(ctx,
		`UPDATE guest_users SET coins = coins + $2, referral_rewarded = TRUE WHERE id = $1`,
		guestID, ReferralBonus); err != nil {
		return false, uuid.Nil, err
	}
	if _, err = tx.Exec(ctx,
		`UPDATE guest_users SET coins = coins + $2 WHERE id = $1`,
		*refID, ReferralBonus); err != nil {
		return false, uuid.Nil, err
	}
	if err = tx.Commit(ctx); err != nil {
		return false, uuid.Nil, err
	}
	return true, *refID, nil
}
