package db

import (
	"context"
	"errors"

	"github.com/google/uuid"
)

var (
	ErrFriendSelf     = errors.New("cannot friend yourself")
	ErrFriendNotFound = errors.New("no such player")
	ErrAlreadyFriends = errors.New("already friends")
)

// Friend is a summary row for the friend list / requests.
type Friend struct {
	ID      uuid.UUID `json:"id"`
	Name    string    `json:"name"`
	RefCode string    `json:"ref_code"`
	Avatar  string    `json:"avatar"`
}

// SendFriendRequest creates a pending request from `from` to the guest with
// `refCode`. If the target already requested `from`, the request is
// auto-accepted (mutual). Idempotent on a duplicate pending request.
func (d *DB) SendFriendRequest(ctx context.Context, from uuid.UUID, refCode string) (autoAccepted bool, err error) {
	var to uuid.UUID
	if e := d.Pool.QueryRow(ctx,
		`SELECT id FROM guest_users WHERE ref_code = $1`, refCode,
	).Scan(&to); e != nil {
		return false, ErrFriendNotFound
	}
	if to == from {
		return false, ErrFriendSelf
	}
	// Already friends?
	var exists bool
	_ = d.Pool.QueryRow(ctx,
		`SELECT EXISTS(SELECT 1 FROM friendships WHERE guest_id=$1 AND friend_id=$2)`,
		from, to).Scan(&exists)
	if exists {
		return false, ErrAlreadyFriends
	}
	// Reverse pending request → accept it now.
	var reverse bool
	_ = d.Pool.QueryRow(ctx,
		`SELECT EXISTS(SELECT 1 FROM friend_requests WHERE from_id=$1 AND to_id=$2)`,
		to, from).Scan(&reverse)
	if reverse {
		if err := d.acceptFriend(ctx, to, from); err != nil {
			return false, err
		}
		return true, nil
	}
	_, err = d.Pool.Exec(ctx,
		`INSERT INTO friend_requests (from_id, to_id) VALUES ($1, $2)
		 ON CONFLICT DO NOTHING`, from, to)
	return false, err
}

// AcceptFriendRequest accepts a pending request from `from` to `me`.
func (d *DB) AcceptFriendRequest(ctx context.Context, me, from uuid.UUID) error {
	var exists bool
	_ = d.Pool.QueryRow(ctx,
		`SELECT EXISTS(SELECT 1 FROM friend_requests WHERE from_id=$1 AND to_id=$2)`,
		from, me).Scan(&exists)
	if !exists {
		return ErrFriendNotFound
	}
	return d.acceptFriend(ctx, from, me)
}

// acceptFriend writes both friendship edges and clears any pending requests
// in either direction, atomically.
func (d *DB) acceptFriend(ctx context.Context, a, b uuid.UUID) error {
	tx, err := d.Pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx) //nolint:errcheck
	if _, err = tx.Exec(ctx,
		`INSERT INTO friendships (guest_id, friend_id) VALUES ($1,$2),($2,$1)
		 ON CONFLICT DO NOTHING`, a, b); err != nil {
		return err
	}
	if _, err = tx.Exec(ctx,
		`DELETE FROM friend_requests
		  WHERE (from_id=$1 AND to_id=$2) OR (from_id=$2 AND to_id=$1)`,
		a, b); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// Friends lists a guest's accepted friends.
func (d *DB) Friends(ctx context.Context, me uuid.UUID) ([]Friend, error) {
	rows, err := d.Pool.Query(ctx, `
		SELECT g.id, g.display_name, COALESCE(g.ref_code,''), COALESCE(g.avatar,'🙂')
		  FROM friendships f JOIN guest_users g ON g.id = f.friend_id
		 WHERE f.guest_id = $1
		 ORDER BY g.display_name`, me)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanFriends(rows)
}

// IncomingRequests lists pending friend requests addressed to `me`.
func (d *DB) IncomingRequests(ctx context.Context, me uuid.UUID) ([]Friend, error) {
	rows, err := d.Pool.Query(ctx, `
		SELECT g.id, g.display_name, COALESCE(g.ref_code,''), COALESCE(g.avatar,'🙂')
		  FROM friend_requests r JOIN guest_users g ON g.id = r.from_id
		 WHERE r.to_id = $1
		 ORDER BY r.created_at DESC`, me)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanFriends(rows)
}

type rowScanner interface {
	Next() bool
	Scan(dest ...any) error
	Err() error
}

func scanFriends(rows rowScanner) ([]Friend, error) {
	var out []Friend
	for rows.Next() {
		var f Friend
		if err := rows.Scan(&f.ID, &f.Name, &f.RefCode, &f.Avatar); err != nil {
			return nil, err
		}
		out = append(out, f)
	}
	return out, rows.Err()
}
