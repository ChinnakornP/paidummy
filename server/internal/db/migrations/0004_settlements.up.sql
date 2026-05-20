-- Per-match per-player coin settlement audit. Feeds:
--   • my coin history       (filter by guest_id)
--   • room game history     (join via matches.room_id)
--   • rank derivation       (count matches_won, sum coin_delta)
CREATE TABLE IF NOT EXISTS match_settlements (
    id            UUID PRIMARY KEY,
    match_id      UUID NOT NULL REFERENCES matches (id) ON DELETE CASCADE,
    guest_id      UUID NOT NULL REFERENCES guest_users (id),
    coin_delta    INT  NOT NULL,         -- positive for winner, negative for losers
    balance_after BIGINT NOT NULL,
    is_winner     BOOLEAN NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_settlements_guest ON match_settlements (guest_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_settlements_match ON match_settlements (match_id);
