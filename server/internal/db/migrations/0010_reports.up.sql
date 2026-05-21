-- Player reports + a ban flag for light moderation. reports is an append-
-- only audit; guest_users.banned gates the auth middleware.
ALTER TABLE guest_users
    ADD COLUMN IF NOT EXISTS banned BOOLEAN NOT NULL DEFAULT FALSE;

CREATE TABLE IF NOT EXISTS reports (
    id          UUID PRIMARY KEY,
    reporter_id UUID NOT NULL REFERENCES guest_users (id) ON DELETE CASCADE,
    target_id   UUID NOT NULL REFERENCES guest_users (id) ON DELETE CASCADE,
    reason      TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_reports_target ON reports (target_id, created_at DESC);
