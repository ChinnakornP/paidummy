// Package session issues and resolves passwordless guest sessions, backed by
// Postgres for durability and Redis as a fast token->guest cache.
package session

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"time"

	"github.com/andaseacode/paidummy-server/internal/db"
	"github.com/andaseacode/paidummy-server/internal/store"
	"github.com/google/uuid"
)

// Guest is the resolved identity behind a session token.
type Guest struct {
	ID    uuid.UUID `json:"id"`
	Name  string    `json:"name"`
	Token string    `json:"token,omitempty"`
	Coins int64     `json:"coins"`
}

// Manager creates and validates sessions.
type Manager struct {
	db  *db.DB
	rds *store.Store
	ttl time.Duration
}

func NewManager(d *db.DB, r *store.Store, ttl time.Duration) *Manager {
	return &Manager{db: d, rds: r, ttl: ttl}
}

func newToken() (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

func cacheKey(token string) string { return "sess:" + token }

// CreateGuest registers a new guest user and an associated session token.
// If [ref] is non-empty and matches another guest's ref_code, the new guest
// is wired as that guest's referee — the +500 referral bonus fires later,
// after the new guest finishes their first match.
func (m *Manager) CreateGuest(ctx context.Context, name, ref string) (Guest, error) {
	if name == "" {
		name = "Player"
	}
	g, err := m.db.CreateGuest(ctx, name)
	if err != nil {
		return Guest{}, err
	}
	_, _ = m.db.EnsureRefCode(ctx, g.ID)
	if ref != "" {
		_, _, _ = m.db.SetReferrer(ctx, g.ID, ref)
	}
	token, err := newToken()
	if err != nil {
		return Guest{}, err
	}
	if err := m.db.CreateSession(ctx, token, g.ID, time.Now().Add(m.ttl)); err != nil {
		return Guest{}, err
	}
	// Best-effort cache; absence just falls back to Postgres.
	_ = m.rds.R.Set(ctx, cacheKey(token), g.ID.String()+"|"+g.DisplayName, m.ttl).Err()
	return Guest{ID: g.ID, Name: g.DisplayName, Token: token, Coins: g.Coins}, nil
}

// Resolve validates a token and returns the guest. Redis is consulted first;
// on a miss it falls back to Postgres and repopulates the cache.
func (m *Manager) Resolve(ctx context.Context, token string) (Guest, bool) {
	if token == "" {
		return Guest{}, false
	}
	if v, err := m.rds.R.Get(ctx, cacheKey(token)).Result(); err == nil {
		if id, name, ok := splitCached(v); ok {
			return Guest{ID: id, Name: name}, true
		}
	}
	g, ok, err := m.db.LookupSession(ctx, token)
	if err != nil || !ok {
		return Guest{}, false
	}
	_ = m.rds.R.Set(ctx, cacheKey(token), g.ID.String()+"|"+g.DisplayName, m.ttl).Err()
	return Guest{ID: g.ID, Name: g.DisplayName, Coins: g.Coins}, true
}

func splitCached(v string) (uuid.UUID, string, bool) {
	for i := 0; i < len(v); i++ {
		if v[i] == '|' {
			id, err := uuid.Parse(v[:i])
			if err != nil {
				return uuid.Nil, "", false
			}
			return id, v[i+1:], true
		}
	}
	return uuid.Nil, "", false
}
