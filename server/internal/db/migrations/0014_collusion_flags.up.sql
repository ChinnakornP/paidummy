-- Anti-collusion flags written by a periodic background scan. Each row is a
-- (winner, loser) pair that co-occurred in suspiciously many finished
-- matches with the winner always winning. Read-only signal for moderation.
CREATE TABLE IF NOT EXISTS collusion_flags (
    id         UUID PRIMARY KEY,
    winner_id  UUID NOT NULL REFERENCES guest_users (id) ON DELETE CASCADE,
    loser_id   UUID NOT NULL REFERENCES guest_users (id) ON DELETE CASCADE,
    matches    INT  NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_collusion_created ON collusion_flags (created_at DESC);
