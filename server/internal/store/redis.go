// Package store is the Redis-backed live layer: ephemeral room/game snapshots,
// presence, the open-room index, and per-room pub/sub fan-out.
package store

import (
	"context"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"
)

// Store wraps a redis client and namespaces all keys.
type Store struct{ R *redis.Client }

// Connect dials redis and pings it.
func Connect(ctx context.Context, addr string) (*Store, error) {
	c := redis.NewClient(&redis.Options{Addr: addr})
	if err := c.Ping(ctx).Err(); err != nil {
		return nil, fmt.Errorf("redis ping: %w", err)
	}
	return &Store{R: c}, nil
}

func (s *Store) Close() error { return s.R.Close() }

func roomKey(id string) string     { return "room:" + id }
func gameKey(id string) string     { return "game:" + id }
func presenceKey(id string) string { return "presence:" + id }
func eventsChan(id string) string  { return "room.events." + id }

const roomsIndex = "rooms:index"

// SaveRoom stores room metadata JSON and indexes it as open if open is true.
func (s *Store) SaveRoom(ctx context.Context, id string, metaJSON []byte, open bool) error {
	if err := s.R.Set(ctx, roomKey(id), metaJSON, 24*time.Hour).Err(); err != nil {
		return err
	}
	if open {
		return s.R.SAdd(ctx, roomsIndex, id).Err()
	}
	return s.R.SRem(ctx, roomsIndex, id).Err()
}

// GetRoom returns the stored room metadata JSON, or (nil,false) if absent.
func (s *Store) GetRoom(ctx context.Context, id string) ([]byte, bool, error) {
	v, err := s.R.Get(ctx, roomKey(id)).Bytes()
	if err == redis.Nil {
		return nil, false, nil
	}
	if err != nil {
		return nil, false, err
	}
	return v, true, nil
}

// ListOpenRooms returns the ids of rooms currently advertised as open.
func (s *Store) ListOpenRooms(ctx context.Context) ([]string, error) {
	return s.R.SMembers(ctx, roomsIndex).Result()
}

// SaveGame writes the authoritative game snapshot (server-only; never sent raw
// to clients). Used after every applied action and read on reconnection.
func (s *Store) SaveGame(ctx context.Context, matchID string, snapshot []byte) error {
	return s.R.Set(ctx, gameKey(matchID), snapshot, 24*time.Hour).Err()
}

// LoadGame reads a game snapshot for rehydration.
func (s *Store) LoadGame(ctx context.Context, matchID string) ([]byte, bool, error) {
	v, err := s.R.Get(ctx, gameKey(matchID)).Bytes()
	if err == redis.Nil {
		return nil, false, nil
	}
	if err != nil {
		return nil, false, err
	}
	return v, true, nil
}

// ClearGame removes a finished game snapshot.
func (s *Store) ClearGame(ctx context.Context, matchID string) error {
	return s.R.Del(ctx, gameKey(matchID)).Err()
}

// Heartbeat records that guest is present in room (TTL-based liveness).
func (s *Store) Heartbeat(ctx context.Context, roomID, guestID string) error {
	return s.R.HSet(ctx, presenceKey(roomID), guestID, time.Now().Unix()).Err()
}

// Publish fans an event payload out to all subscribers of a room.
func (s *Store) Publish(ctx context.Context, roomID string, payload []byte) error {
	return s.R.Publish(ctx, eventsChan(roomID), payload).Err()
}

// Subscribe returns a pubsub subscription for a room's event channel. The
// caller must Close the returned *redis.PubSub.
func (s *Store) Subscribe(ctx context.Context, roomID string) *redis.PubSub {
	return s.R.Subscribe(ctx, eventsChan(roomID))
}
